(* The AST for the Phase-2 / concept-05 subset — a *contract* (fully written). Carries
   Phase 1's nodes forward and adds: Double/Bool/String literals, the comparison binops,
   and an optional type annotation on bindings (`let x: Double = …`).

   Design oracle: swift/include/swift/AST/{Expr,Stmt,Decl}.h *)

type binop =
  | Add
  | Sub
  | Mul
  | Div
  | Mod (* arithmetic *)
  | Eq
  | Ne
  | Lt
  | Le
  | Gt
  | Ge (* comparison -> Bool *)

type unop = Neg

type expr =
  | Int_lit of int * Token.span
  | Double_lit of float * Token.span (* NEW *)
  | Bool_lit of bool * Token.span (* NEW *)
  | String_lit of string * Token.span (* NEW *)
  | Var of string * Token.span
  | Unary of unop * expr * Token.span
  | Binary of binop * expr * expr * Token.span
  | Call of string * expr list * Token.span

type stmt =
  | Let of {
      name : string;
      is_var : bool;
      annot : string option; (* NEW: the written type name, e.g. Some "Double"; sema resolves it *)
      value : expr;
      span : Token.span;
    }
  | Assign of { name : string; value : expr; span : Token.span }
  | Expr_stmt of expr * Token.span

type program = { stmts : stmt list }

let expr_span = function
  | Int_lit (_, s)
  | Double_lit (_, s)
  | Bool_lit (_, s)
  | String_lit (_, s)
  | Var (_, s)
  | Unary (_, _, s)
  | Binary (_, _, _, s)
  | Call (_, _, s) ->
      s

let string_of_binop = function
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Div -> "/"
  | Mod -> "%"
  | Eq -> "=="
  | Ne -> "!="
  | Lt -> "<"
  | Le -> "<="
  | Gt -> ">"
  | Ge -> ">="

let string_of_unop = function Neg -> "-"

(* Compact S-expression dump for `--emit-ast` and AST unit tests. *)
let rec dump_expr = function
  | Int_lit (n, _) -> string_of_int n
  | Double_lit (f, _) -> Printf.sprintf "%g" f
  | Bool_lit (b, _) -> string_of_bool b
  | String_lit (s, _) -> Printf.sprintf "%S" s
  | Var (x, _) -> x
  | Unary (op, e, _) -> Printf.sprintf "(%s %s)" (string_of_unop op) (dump_expr e)
  | Binary (op, l, r, _) ->
      Printf.sprintf "(%s %s %s)" (string_of_binop op) (dump_expr l) (dump_expr r)
  | Call (f, args, _) -> Printf.sprintf "(%s %s)" f (String.concat " " (List.map dump_expr args))

let dump_stmt = function
  | Let { name; is_var; annot; value; _ } ->
      let kw = if is_var then "var" else "let" in
      (match annot with
      | None -> Printf.sprintf "(%s %s %s)" kw name (dump_expr value)
      | Some t -> Printf.sprintf "(%s %s : %s %s)" kw name t (dump_expr value))
  | Assign { name; value; _ } -> Printf.sprintf "(= %s %s)" name (dump_expr value)
  | Expr_stmt (e, _) -> dump_expr e

let dump_program (p : program) : string = String.concat "\n" (List.map dump_stmt p.stmts)
