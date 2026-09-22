(* The TYPE-CHECKED AST for concept 06 — a *contract* (given).

   `Ast` is what the PARSER produces: a faithful record of what was written, with no types and
   no names resolved. `Tast` is what SEMA produces, and it is a different type on purpose:

     - **every node carries its type.** Later stages need those types constantly — SILGen picks
       a SIL instruction by them — but they read the answer here instead of deriving it again.
     - **names are resolved.** `Ast.Var "x"` could be a local or an unknown; `Tast.Local "x"`
       can only be a local. `Ast.Call (f, args)` is a name still to be resolved; `Tast.Print`
       is print and nothing else.
     - **implicit conversions are explicit nodes.** There are none yet in this subset — the
       first arrives with optionals (13), then protocols (21) and classes (25) — but the shape
       is here.

   The point of the split is that it makes a class of bug UNREPRESENTABLE. SILGen (concept 08)
   matches on `Tast`, whose constructors are all resolved, so it cannot re-derive a decision the
   checker already made — and it cannot disagree with it. See PLAN.md §0.1 for the history that
   led here, including a real fix that reached 23 of 44 copies of a duplicated decision.

   Design oracle: swift/include/swift/AST/Expr.h — `Expr` carries `Type Ty` with
   getType()/setType() (line 406), and lib/Sema/CSApply.cpp is the pass that fills it in,
   "resulting in a fully-type-checked expression". You can see the result for real:

       swiftc -dump-ast x.swift

   On `let d = 1.5; print(d * 2)` that prints `integer_literal_expr type="Double"` — swiftc
   does not rewrite the `2` into a floating-point literal, it keeps the node and gives it the
   type the solver chose. `Tast` does exactly the same: the node below still says `Int_lit 2`,
   and its `ty` says `TDouble`. Concept 08's SILGen reads `ty` to decide what to emit. *)

type expr = {
  e : expr_kind;
  ty : Types.ty; (* what the checker concluded — swiftc's `Expr::Ty` *)
  span : Token.span; (* kept for diagnostics, as swiftc keeps source ranges *)
}

and expr_kind =
  | Int_lit of int
      (* `ty` may be TInt OR TDouble: an integer literal beside a Double adopts it, and this is
         where that is recorded. swiftc: `integer_literal_expr type="Double"`. *)
  | Double_lit of float
  | Bool_lit of bool
  | String_lit of string
  | Local of string (* RESOLVED: a binding that is in scope. Never an unknown name. *)
  | Unary of Ast.unop * expr
  | Binary of Ast.binop * expr * expr
  | Print of expr (* RESOLVED: `print(_:)`, the only function this subset has *)
  | Coerce of expr
      (* `e as T`. Semantically a no-op once the operand has been checked at T, but swiftc keeps
         the node too (`coerce_expr`), so the tree still records what the source said. *)

type stmt =
  | Let of { name : string; is_var : bool; value : expr; span : Token.span }
      (* the annotation is gone: it was a WRITTEN name, and `value.ty` is the resolved answer *)
  | Assign of { name : string; value : expr; span : Token.span }
  | Expr_stmt of expr
  (* control flow — NEW in this concept. A block is a [stmt list], as in the Ast. *)
  | If of { cond : expr; then_blk : stmt list; else_blk : stmt list option; span : Token.span }
  | While of { cond : expr; body : stmt list; span : Token.span }
  | For of { var : string; lo : expr; hi : expr; body : stmt list; span : Token.span }
  | Break of Token.span
  | Continue of Token.span
type program = { stmts : stmt list }

(* -- printing, for `--emit-tast` and the tests ------------------------------------------
   Deliberately shaped like `swiftc -dump-ast`: every line names the node and its type, so the
   two can be read side by side. *)
let rec dump_expr (x : expr) : string =
  let t = Types.string_of_ty x.ty in
  match x.e with
  | Int_lit n -> Printf.sprintf "(int_lit %d : %s)" n t
  | Double_lit f -> Printf.sprintf "(double_lit %g : %s)" f t
  | Bool_lit b -> Printf.sprintf "(bool_lit %b : %s)" b t
  | String_lit s -> Printf.sprintf "(string_lit %S : %s)" s t
  | Local x' -> Printf.sprintf "(local %s : %s)" x' t
  | Unary (op, e0) -> Printf.sprintf "(%s %s : %s)" (Ast.string_of_unop op) (dump_expr e0) t
  | Binary (op, l, r) ->
      Printf.sprintf "(%s %s %s : %s)" (Ast.string_of_binop op) (dump_expr l) (dump_expr r) t
  | Print e0 -> Printf.sprintf "(print %s : %s)" (dump_expr e0) t
  | Coerce e0 -> Printf.sprintf "(coerce %s : %s)" (dump_expr e0) t

let rec dump_stmt = function
  | Let { name; is_var; value; _ } ->
      Printf.sprintf "(%s %s %s)" (if is_var then "var" else "let") name (dump_expr value)
  | Assign { name; value; _ } -> Printf.sprintf "(= %s %s)" name (dump_expr value)
  | Expr_stmt e -> dump_expr e
  | If { cond; then_blk; else_blk; _ } ->
      Printf.sprintf "(if %s %s%s)" (dump_expr cond) (dump_block then_blk)
        (match else_blk with None -> "" | Some b -> " " ^ dump_block b)
  | While { cond; body; _ } -> Printf.sprintf "(while %s %s)" (dump_expr cond) (dump_block body)
  | For { var; lo; hi; body; _ } ->
      Printf.sprintf "(for %s %s %s %s)" var (dump_expr lo) (dump_expr hi) (dump_block body)
  | Break _ -> "(break)"
  | Continue _ -> "(continue)"

and dump_block b = Printf.sprintf "{%s}" (String.concat " " (List.map dump_stmt b))

let dump_program (p : program) : string = String.concat "\n" (List.map dump_stmt p.stmts)
