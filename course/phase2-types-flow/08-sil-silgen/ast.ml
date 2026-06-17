(* AST for concept 07 — a *contract*. Concept-06 nodes + functions: a parameter, a
   function declaration, a `return` statement, and a top-level *item* that is either a
   function or a statement (so a program is an interleaving of the two).

   Design oracle: swift/include/swift/AST/Decl.h (FuncDecl, ParamDecl), Stmt.h (ReturnStmt). *)

type binop =
  | Add | Sub | Mul | Div | Mod
  | Eq | Ne | Lt | Le | Gt | Ge
  | And | Or

type unop = Neg

type expr =
  | Int_lit of int * Token.span
  | Double_lit of float * Token.span
  | Bool_lit of bool * Token.span
  | String_lit of string * Token.span
  | Var of string * Token.span
  | Unary of unop * expr * Token.span
  | Binary of binop * expr * expr * Token.span
  | Call of string * expr list * Token.span

type stmt =
  | Let of { name : string; is_var : bool; annot : string option; value : expr; span : Token.span }
  | Assign of { name : string; value : expr; span : Token.span }
  | Expr_stmt of expr * Token.span
  | If of { cond : expr; then_blk : stmt list; else_blk : stmt list option; span : Token.span }
  | While of { cond : expr; body : stmt list; span : Token.span }
  | For of { var : string; lo : expr; hi : expr; body : stmt list; span : Token.span }
  | Break of Token.span
  | Continue of Token.span
  | Return of expr option * Token.span (* NEW: `return` or `return e` *)

(* NEW: functions *)
type param = { pname : string; ptype : string (* written type name; sema resolves it *) }

type func_decl = {
  fname : string;
  params : param list;
  ret : string option; (* the written return type name; None = Void *)
  body : stmt list;
  fspan : Token.span;
}

type item =
  | IFunc of func_decl
  | IStmt of stmt

type program = { items : item list }

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
  | Add -> "+" | Sub -> "-" | Mul -> "*" | Div -> "/" | Mod -> "%"
  | Eq -> "==" | Ne -> "!=" | Lt -> "<" | Le -> "<=" | Gt -> ">" | Ge -> ">="
  | And -> "&&" | Or -> "||"

let string_of_unop = function Neg -> "-"

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

let rec dump_stmt = function
  | Let { name; is_var; annot; value; _ } ->
      let kw = if is_var then "var" else "let" in
      (match annot with
      | None -> Printf.sprintf "(%s %s %s)" kw name (dump_expr value)
      | Some t -> Printf.sprintf "(%s %s : %s %s)" kw name t (dump_expr value))
  | Assign { name; value; _ } -> Printf.sprintf "(= %s %s)" name (dump_expr value)
  | Expr_stmt (e, _) -> dump_expr e
  | If { cond; then_blk; else_blk; _ } -> (
      match else_blk with
      | None -> Printf.sprintf "(if %s %s)" (dump_expr cond) (dump_block then_blk)
      | Some e -> Printf.sprintf "(if %s %s %s)" (dump_expr cond) (dump_block then_blk) (dump_block e))
  | While { cond; body; _ } -> Printf.sprintf "(while %s %s)" (dump_expr cond) (dump_block body)
  | For { var; lo; hi; body; _ } ->
      Printf.sprintf "(for %s %s %s %s)" var (dump_expr lo) (dump_expr hi) (dump_block body)
  | Break _ -> "break"
  | Continue _ -> "continue"
  | Return (None, _) -> "(return)"
  | Return (Some e, _) -> Printf.sprintf "(return %s)" (dump_expr e)

and dump_block (stmts : stmt list) : string =
  Printf.sprintf "(%s)" (String.concat " " (List.map dump_stmt stmts))

let dump_param (p : param) : string = Printf.sprintf "%s:%s" p.pname p.ptype

let dump_func (f : func_decl) : string =
  let ps = String.concat " " (List.map dump_param f.params) in
  let ret = match f.ret with Some r -> Printf.sprintf "-> %s " r | None -> "" in
  Printf.sprintf "(func %s (%s) %s%s)" f.fname ps ret (dump_block f.body)

let dump_item = function IFunc f -> dump_func f | IStmt s -> dump_stmt s
let dump_program (p : program) : string = String.concat "\n" (List.map dump_item p.items)
