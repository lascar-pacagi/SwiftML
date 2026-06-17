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
  | Kw_protocol (* NEW (concept 21) *)
  | Kw_where (* NEW (concept 22) *)
  | Kw_as (* NEW (concept 23) *)
  | Kw_class (* NEW (concept 25) *)
  | Kw_init
  | Kw_override
  | Kw_super
  | Kw_deinit (* NEW (concept 26) *)
  | At (* `@` — attributes like `@escaping` (parsed and accepted; concept 29) *)
  | LBracket | RBracket (* `[` `]` — concept 31 *)
  (* error handling — concept 30 *)
  | Kw_throws | Kw_throw | Kw_try | Kw_do | Kw_catch | Kw_defer
  | Kw_async | Kw_await (* concept 38 *)
  | Kw_case (* NEW (concept 11) *)
  | Kw_switch (* NEW (concept 12) *)
  | Kw_default (* NEW (concept 12) *)
  | Kw_nil (* NEW (concept 13) *)
  | Question (* ? — optional type / nil-coalescing *)
  | Bang (* ! — force unwrap *)
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
  | Kw_protocol -> "protocol"
  | Kw_where -> "where"
  | Kw_as -> "as"
  | Kw_class -> "class"
  | Kw_init -> "init"
  | Kw_override -> "override"
  | Kw_super -> "super"
  | Kw_deinit (* NEW (concept 26) *) -> "deinit"
  | At (* `@` — attributes like `@escaping` (parsed and accepted; concept 29) *)
  | LBracket | RBracket (* `[` `]` — concept 31 *) -> "@"
  (* error handling — concept 30 *)
  | Kw_throws -> "throws" | Kw_throw -> "throw" | Kw_try -> "try"
  | Kw_do -> "do" | Kw_catch -> "catch" | Kw_defer -> "defer"
  | Kw_async -> "async" | Kw_await -> "await"
  | Kw_case -> "case"
  | Kw_switch -> "switch"
  | Kw_default -> "default"
  | Kw_nil -> "nil"
  | Question -> "?"
  | Bang -> "!"
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
  | "protocol" -> Kw_protocol
  | "where" -> Kw_where
  | "as" -> Kw_as
  | "class" -> Kw_class
  | "init" -> Kw_init
  | "override" -> Kw_override
  | "super" -> Kw_super
  | "deinit" -> Kw_deinit
  | "throws" -> Kw_throws | "throw" -> Kw_throw | "try" -> Kw_try
  | "do" -> Kw_do | "catch" -> Kw_catch | "defer" -> Kw_defer
  | "async" -> Kw_async | "await" -> Kw_await
  | "case" -> Kw_case
  | "switch" -> Kw_switch
  | "default" -> Kw_default
  | "nil" -> Kw_nil
  | _ -> Ident s
