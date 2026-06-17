(* The abstract syntax tree for the Phase-1 subset. Grows every phase
   (types, functions, structs, enums, generics, classes, closures, …).

   Design oracle:
     swift/include/swift/AST/Expr.h   Stmt.h   Decl.h   Pattern.h
   Swift keeps a very rich AST; ours starts minimal and tracks it.

   This file is a *contract* (fully written). The parser (parser.ml) builds it. *)

type binop =
  | Add
  | Sub
  | Mul
  | Div
  | Mod

type unop = Neg

(* Every node carries its source span so Sema/diagnostics can point at it. *)
type expr =
  | Int_lit of int * Token.span
  | Var of string * Token.span (* a reference to a let/var binding *)
  | Unary of unop * expr * Token.span
  | Binary of binop * expr * expr * Token.span
  | Call of string * expr list * Token.span (* Phase 1: only print(_:) *)

type stmt =
  | Let of {
      name : string;
      is_var : bool; (* `var` vs `let` *)
      value : expr;
      span : Token.span;
    }
  | Assign of {
      (* reassignment of an existing `var`: `c = c * 2`. Mirrors swiftc's AssignExpr,
         kept as a statement for the Phase-1 subset. Sema checks the target is a
         declared, mutable binding. *)
      name : string;
      value : expr;
      span : Token.span;
    }
  | Expr_stmt of expr * Token.span

type program = { stmts : stmt list }

(* Span accessor — handy for diagnostics. *)
let expr_span = function
  | Int_lit (_, s) | Var (_, s) | Unary (_, _, s) | Binary (_, _, _, s) | Call (_, _, s) -> s

let string_of_binop = function
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Div -> "/"
  | Mod -> "%"

let string_of_unop = function Neg -> "-"

(* A compact S-expression dump, used by `swiftml --emit-ast` and AST unit tests. *)
let rec dump_expr = function
  | Int_lit (n, _) -> string_of_int n
  | Var (x, _) -> x
  | Unary (op, e, _) -> Printf.sprintf "(%s %s)" (string_of_unop op) (dump_expr e)
  | Binary (op, l, r, _) ->
      Printf.sprintf "(%s %s %s)" (string_of_binop op) (dump_expr l) (dump_expr r)
  | Call (f, args, _) ->
      Printf.sprintf "(%s %s)" f (String.concat " " (List.map dump_expr args))

let dump_stmt = function
  | Let { name; is_var; value; _ } ->
      Printf.sprintf "(%s %s %s)" (if is_var then "var" else "let") name (dump_expr value)
  | Assign { name; value; _ } -> Printf.sprintf "(= %s %s)" name (dump_expr value)
  | Expr_stmt (e, _) -> dump_expr e

let dump_program (p : program) : string =
  String.concat "\n" (List.map dump_stmt p.stmts)
