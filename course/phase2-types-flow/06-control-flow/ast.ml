(* AST for concept 06 — a *contract*. Concept-05 nodes + control flow: the logical
   binops And/Or, and the If/While/For/Break/Continue statements. A "block" is just a
   [stmt list].

   Design oracle: swift/include/swift/AST/Stmt.h (IfStmt, WhileStmt, ForEachStmt,
   BreakStmt, ContinueStmt, BraceStmt). *)

type binop =
  | Add
  | Sub
  | Mul
  | Div
  | Mod
  | Eq
  | Ne
  | Lt
  | Le
  | Gt
  | Ge
  | And (* && — NEW in this concept *)
  | Or (* || — NEW in this concept *)

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
  | Ascribe of expr * string * Token.span (* `e as T` — a coercion *)

type stmt =
  | Let of { name : string; is_var : bool; annot : string option; value : expr; span : Token.span }
  | Assign of { name : string; value : expr; span : Token.span }
  | Expr_stmt of expr * Token.span
  (* control flow — NEW in this concept *)
  | If of { cond : expr; then_blk : stmt list; else_blk : stmt list option; span : Token.span }
  | While of { cond : expr; body : stmt list; span : Token.span }
  | For of { var : string; lo : expr; hi : expr; body : stmt list; span : Token.span }
      (* `for var in lo ..< hi { body }` — half-open Int range *)
  | Break of Token.span
  | Continue of Token.span

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
  | Ascribe (_, _, s) -> s

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
  | And -> "&&"
  | Or -> "||"

let string_of_unop = function Neg -> "-"

let rec dump_expr = function
  | Int_lit (integer, _) -> string_of_int integer
  | Double_lit (number, _) -> Printf.sprintf "%g" number
  | Bool_lit (boolean, _) -> string_of_bool boolean
  | String_lit (text, _) -> Printf.sprintf "%S" text
  | Var (name, _) -> name
  | Unary (operator, expression, _) ->
      Printf.sprintf "(%s %s)" (string_of_unop operator) (dump_expr expression)
  | Binary (operator, left, right, _) ->
      Printf.sprintf "(%s %s %s)" (string_of_binop operator) (dump_expr left) (dump_expr right)
  | Ascribe (expression, type_name, _) -> Printf.sprintf "(as %s %s)" type_name (dump_expr expression)
  | Call (function_name, arguments, _) ->
      Printf.sprintf "(%s %s)" function_name (String.concat " " (List.map dump_expr arguments))

let rec dump_stmt = function
  | Let { name; is_var; annot; value; _ } ->
      let keyword = if is_var then "var" else "let" in
      (match annot with
      | None -> Printf.sprintf "(%s %s %s)" keyword name (dump_expr value)
      | Some type_name -> Printf.sprintf "(%s %s : %s %s)" keyword name type_name (dump_expr value))
  | Assign { name; value; _ } -> Printf.sprintf "(= %s %s)" name (dump_expr value)
  | Expr_stmt (expression, _) -> dump_expr expression
  | If { cond; then_blk; else_blk; _ } -> (
      match else_blk with
      | None -> Printf.sprintf "(if %s %s)" (dump_expr cond) (dump_block then_blk)
      | Some statements ->
          Printf.sprintf "(if %s %s %s)" (dump_expr cond) (dump_block then_blk)
            (dump_block statements))
  | While { cond; body; _ } -> Printf.sprintf "(while %s %s)" (dump_expr cond) (dump_block body)
  | For { var; lo; hi; body; _ } ->
      Printf.sprintf "(for %s %s %s %s)" var (dump_expr lo) (dump_expr hi) (dump_block body)
  | Break _ -> "break"
  | Continue _ -> "continue"

and dump_block (statements : stmt list) : string =
  Printf.sprintf "(%s)" (String.concat " " (List.map dump_stmt statements))

let dump_program (program : program) : string =
  String.concat "\n" (List.map dump_stmt program.stmts)
