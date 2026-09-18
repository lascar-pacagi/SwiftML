(* The TYPE-CHECKED AST for concept 12 — a *contract* (given).

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
  | Print of expr (* RESOLVED: `print(_:)` — a call that IS print, not a name that might be *)
  | Fn_call of string * expr list
      (* RESOLVED: a call to a function declared in this program. `Ast.Call` could be either of
         these, a struct initializer, or an unknown name; which one it was is decided once. *)
  | Struct_init of string * expr list
      (* RESOLVED: `Point(x: 1, y: 2)`. The arguments are in LAYOUT ORDER and the labels are
         gone — they were checked against the field names, and having served that purpose they
         carry no further meaning. *)
  | Enum_case of string * int * expr list
      (* RESOLVED: `E.red` / `E.some(1)` as the enum name and its TAG. `E.red` and `p.x` parse to
         the SAME tree (`Ast.Member` over an `Ast.Var`), so only name resolution can say which is
         which — and Swift's rule is that a value binding SHADOWS a type name. Deciding once and
         recording it here is what makes the two stages unable to disagree; PLAN.md §0.1 has the
         miscompile that came of deciding twice. swiftc: lib/SILGen never sees UnresolvedDotExpr. *)
  | Raw_value of expr (* RESOLVED: `e.rawValue` on a raw-value enum — the tag, as an Int *)
  | Field of expr * int * string
      (* RESOLVED: `p.x` as a field INDEX (the name is kept only for printing). swiftc's
         resolved member reference carries a decl; ours carries the position, which is what the
         back end actually needs — so SILGen performs no lookup at all. *)
  | Coerce of expr
      (* `e as T`. Semantically a no-op once the operand has been checked at T, but swiftc keeps
         the node too (`coerce_expr`), so the tree still records what the source said. *)

(* A RESOLVED pattern. The source writes a case NAME; the checker turns it into the TAG, and
   each binding carries the type of the payload slot it names — so the dispatch lowering has
   nothing left to look up, and cannot disagree about which case is which. *)
type pat_binding = Bind of string * Types.ty | Ignore
type pattern = PEnumCase of int * pat_binding list | PInt of int

type stmt =
  | Let of { name : string; is_var : bool; value : expr; span : Token.span }
      (* the annotation is gone: it was a WRITTEN name, and `value.ty` is the resolved answer *)
  | Assign of { name : string; value : expr; span : Token.span }
  | Expr_stmt of expr
  (* control flow — concept 06. A block is a [stmt list], as in the Ast. *)
  | If of { cond : expr; then_blk : stmt list; else_blk : stmt list option; span : Token.span }
  | While of { cond : expr; body : stmt list; span : Token.span }
  | For of { var : string; lo : expr; hi : expr; body : stmt list; span : Token.span }
  | Break of Token.span
  | Continue of Token.span
  | Return of expr option * Token.span (* concept 07 *)
  | Switch of {
      subject : expr;
      cases : (pattern * stmt list) list;
      default : stmt list option;
      span : Token.span;
    }
  | Set_member of {
      obj : string;
      field : int; (* RESOLVED index, as in `Field` above *)
      field_name : string; (* for printing only *)
      value : expr;
      span : Token.span;
    }
(* a function whose signature is RESOLVED: the written type names are gone, replaced by the
   types they named. Nothing downstream re-resolves a parameter type. *)
type param = { pname : string; pty : Types.ty }

type func_decl = {
  fname : string;
  params : param list;
  ret : Types.ty; (* TVoid when none was written *)
  body : stmt list;
  fspan : Token.span;
}

(* The struct layouts Sema built. SILGen receives them rather than rebuilding them from
   declarations, so the field order it lowers is the one the checker type-checked against. *)
type item =
  | IFunc of func_decl
  | IStruct of Types.struct_layout
  | IEnum of Types.enum_layout
  | IStmt of stmt
type program = { items : item list }

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
  | Fn_call (f, args) ->
      Printf.sprintf "(call %s%s : %s)" f
        (String.concat "" (List.map (fun a -> " " ^ dump_expr a) args)) t
  | Struct_init (sn, args) ->
      Printf.sprintf "(init %s%s : %s)" sn
        (String.concat "" (List.map (fun a -> " " ^ dump_expr a) args)) t
  | Field (e0, i, name) -> Printf.sprintf "(field %s #%d %s : %s)" (dump_expr e0) i name t
  | Enum_case (en, tag, []) -> Printf.sprintf "(case %s #%d : %s)" en tag t
  | Enum_case (en, tag, args) ->
      Printf.sprintf "(case %s #%d%s : %s)" en tag
        (String.concat "" (List.map (fun a -> " " ^ dump_expr a) args)) t
  | Raw_value e0 -> Printf.sprintf "(rawValue %s : %s)" (dump_expr e0) t
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
  | Return (None, _) -> "(return)"
  | Return (Some e, _) -> Printf.sprintf "(return %s)" (dump_expr e)
  | Switch { subject; cases; default; _ } ->
      let dump_bind = function Bind (x, t) -> x ^ ":" ^ Types.string_of_ty t | Ignore -> "_" in
      let dump_pat = function
        | PEnumCase (tag, []) -> Printf.sprintf "#%d" tag
        | PEnumCase (tag, bs) ->
            Printf.sprintf "#%d(%s)" tag (String.concat "," (List.map dump_bind bs))
        | PInt n -> string_of_int n
      in
      Printf.sprintf "(switch %s%s%s)" (dump_expr subject)
        (String.concat ""
           (List.map (fun (p, b) -> Printf.sprintf " [%s %s]" (dump_pat p) (dump_block b)) cases))
        (match default with None -> "" | Some d -> " [default " ^ dump_block d ^ "]")
  | Set_member { obj; field; field_name; value; _ } ->
      Printf.sprintf "(set-field %s #%d %s %s)" obj field field_name (dump_expr value)

and dump_block b = Printf.sprintf "{%s}" (String.concat " " (List.map dump_stmt b))

let dump_func (f : func_decl) : string =
  Printf.sprintf "(func %s (%s) -> %s %s)" f.fname
    (String.concat " " (List.map (fun p -> Printf.sprintf "%s:%s" p.pname (Types.string_of_ty p.pty)) f.params))
    (Types.string_of_ty f.ret) (dump_block f.body)

let dump_item = function
  | IFunc f -> dump_func f
  | IStruct l ->
      Printf.sprintf "(struct %s%s)" l.Types.sl_name
        (String.concat ""
           (List.map (fun (n, t) -> Printf.sprintf " %s:%s" n (Types.string_of_ty t))
              l.Types.sl_fields))
  | IEnum l ->
      Printf.sprintf "(enum %s%s)" l.Types.el_name
        (String.concat ""
           (List.map (fun (n, tys) ->
                Printf.sprintf " %s/%d" n (List.length tys)) l.Types.el_cases))
  | IStmt s -> dump_stmt s
let dump_program (p : program) : string = String.concat "\n" (List.map dump_item p.items)
