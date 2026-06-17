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
  | Call of string * (string option * expr) list * Token.span (* function call OR struct init *)
  | Member of expr * string * Token.span (* NEW (concept 10): `e.field` *)

(* a call/init argument may carry an external label, e.g. `Point(x: 1)` — concept 10 *)
type arg = string option * expr

type stmt =
  | Let of { name : string; is_var : bool; annot : string option; value : expr; span : Token.span }
  | Assign of { name : string; value : expr; span : Token.span }
  | Set_member of { obj : string; field : string; value : expr; span : Token.span } (* NEW: `p.x = e` *)
  | Expr_stmt of expr * Token.span
  | If of { cond : expr; then_blk : stmt list; else_blk : stmt list option; span : Token.span }
  | While of { cond : expr; body : stmt list; span : Token.span }
  | For of { var : string; lo : expr; hi : expr; body : stmt list; span : Token.span }
  | Break of Token.span
  | Continue of Token.span
  | Return of expr option * Token.span

(* NEW: functions *)
type param = { pname : string; ptype : string (* written type name; sema resolves it *) }

type func_decl = {
  fname : string;
  params : param list;
  ret : string option; (* the written return type name; None = Void *)
  body : stmt list;
  fspan : Token.span;
}

(* NEW (concept 10): a struct declaration — stored properties in order *)
type field = { fld_name : string; fld_ty : string (* written type name; sema resolves it *) }
type struct_decl = { sname : string; sfields : field list; sspan : Token.span }

type item =
  | IFunc of func_decl
  | IStruct of struct_decl
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
  | Call (_, _, s)
  | Member (_, _, s) ->
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
  | Call (f, args, _) ->
      let darg (l, e) = match l with Some lbl -> Printf.sprintf "%s:%s" lbl (dump_expr e) | None -> dump_expr e in
      Printf.sprintf "(%s %s)" f (String.concat " " (List.map darg args))
  | Member (e, fld, _) -> Printf.sprintf "(. %s %s)" (dump_expr e) fld

let rec dump_stmt = function
  | Let { name; is_var; annot; value; _ } ->
      let kw = if is_var then "var" else "let" in
      (match annot with
      | None -> Printf.sprintf "(%s %s %s)" kw name (dump_expr value)
      | Some t -> Printf.sprintf "(%s %s : %s %s)" kw name t (dump_expr value))
  | Assign { name; value; _ } -> Printf.sprintf "(= %s %s)" name (dump_expr value)
  | Set_member { obj; field; value; _ } -> Printf.sprintf "(.= %s %s %s)" obj field (dump_expr value)
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

let dump_field (f : field) : string = Printf.sprintf "%s:%s" f.fld_name f.fld_ty
let dump_struct (s : struct_decl) : string =
  Printf.sprintf "(struct %s (%s))" s.sname (String.concat " " (List.map dump_field s.sfields))

let dump_item = function IFunc f -> dump_func f | IStruct s -> dump_struct s | IStmt s -> dump_stmt s
let dump_program (p : program) : string = String.concat "\n" (List.map dump_item p.items)
