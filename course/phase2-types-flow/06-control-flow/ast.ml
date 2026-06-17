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
  | And (* && NEW *)
  | Or (* || NEW *)

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
  (* control flow (NEW) *)
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

and dump_block (stmts : stmt list) : string =
  Printf.sprintf "(%s)" (String.concat " " (List.map dump_stmt stmts))

let dump_program (p : program) : string = String.concat "\n" (List.map dump_stmt p.stmts)
