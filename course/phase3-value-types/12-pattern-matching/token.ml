(* Tokens for concept 07 — a *contract*. Concept-06 tokens + functions: the keywords
   func/return and the arrow -> (for return types). *)

type pos = { line : int; col : int; offset : int }
type span = { lo : pos; hi : pos }

let dummy_pos = { line = 0; col = 0; offset = 0 }
let dummy_span = { lo = dummy_pos; hi = dummy_pos }

type kind =
  | Int of int
  | Float of float
  | String of string
  | Ident of string
  | Kw_let
  | Kw_var
  | Kw_true
  | Kw_false
  | Kw_if
  | Kw_else
  | Kw_while
  | Kw_for
  | Kw_in
  | Kw_break
  | Kw_continue
  | Kw_func
  | Kw_return
  | Kw_struct
  | Kw_enum (* NEW (concept 11) *)
  | Kw_case (* NEW (concept 11) *)
  | Kw_switch (* NEW (concept 12) *)
  | Kw_default (* NEW (concept 12) *)
  | Plus
  | Minus
  | Star
  | Slash
  | Percent
  | Eq
  | EqEq
  | Ne
  | Lt
  | Le
  | Gt
  | Ge
  | AmpAmp
  | PipePipe
  | DotDotLt
  | Arrow
  | Dot (* . member access — NEW (concept 10) *)
  | Colon
  | LParen
  | RParen
  | LBrace
  | RBrace
  | Comma
  | Newline
  | Eof

type t = { kind : kind; span : span }

let string_of_kind = function
  | Int n -> Printf.sprintf "int(%d)" n
  | Float f -> Printf.sprintf "float(%g)" f
  | String s -> Printf.sprintf "string(%S)" s
  | Ident s -> Printf.sprintf "ident(%s)" s
  | Kw_let -> "let"
  | Kw_var -> "var"
  | Kw_true -> "true"
  | Kw_false -> "false"
  | Kw_if -> "if"
  | Kw_else -> "else"
  | Kw_while -> "while"
  | Kw_for -> "for"
  | Kw_in -> "in"
  | Kw_break -> "break"
  | Kw_continue -> "continue"
  | Kw_func -> "func"
  | Kw_return -> "return"
  | Kw_struct -> "struct"
  | Kw_enum -> "enum"
  | Kw_case -> "case"
  | Kw_switch -> "switch"
  | Kw_default -> "default"
  | Plus -> "+"
  | Minus -> "-"
  | Star -> "*"
  | Slash -> "/"
  | Percent -> "%"
  | Eq -> "="
  | EqEq -> "=="
  | Ne -> "!="
  | Lt -> "<"
  | Le -> "<="
  | Gt -> ">"
  | Ge -> ">="
  | AmpAmp -> "&&"
  | PipePipe -> "||"
  | DotDotLt -> "..<"
  | Arrow -> "->"
  | Dot -> "."
  | Colon -> ":"
  | LParen -> "("
  | RParen -> ")"
  | LBrace -> "{"
  | RBrace -> "}"
  | Comma -> ","
  | Newline -> "newline"
  | Eof -> "eof"

let keyword_or_ident (s : string) : kind =
  match s with
  | "let" -> Kw_let
  | "var" -> Kw_var
  | "true" -> Kw_true
  | "false" -> Kw_false
  | "if" -> Kw_if
  | "else" -> Kw_else
  | "while" -> Kw_while
  | "for" -> Kw_for
  | "in" -> Kw_in
  | "break" -> Kw_break
  | "continue" -> Kw_continue
  | "func" -> Kw_func
  | "return" -> Kw_return
  | "struct" -> Kw_struct
  | "enum" -> Kw_enum
  | "case" -> Kw_case
  | "switch" -> Kw_switch
  | "default" -> Kw_default
  | _ -> Ident s
