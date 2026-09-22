(* CONTRACT — concept 06, WITH §6's EXERCISES APPLIED. Run it with
   `make check-exercises C=phase2-types-flow/06-control-flow`.
   EX1 adds the `repeat` keyword, EX2 the `...` operator. *)

(* Tokens for concept 06 — a *contract*. Concept-05 tokens + control flow: the keywords
   if/else/while/for/in/break/continue, the logical operators && ||, the half-open range
   ..<, and braces { }.

   Design oracle: swift/include/swift/Syntax/TokenKinds.def *)

type pos = { line : int; col : int; offset : int }
type span = { lo : pos; hi : pos }

let dummy_pos = { line = 0; col = 0; offset = 0 }
let dummy_span = { lo = dummy_pos; hi = dummy_pos }

type kind =
  | Int of int
  | Float of float
  | String of string
  | Ident of string
  (* keywords *)
  | Kw_let
  | Kw_var
  | Kw_true
  | Kw_false
  | Kw_as
  (* control flow (NEW) *)
  | Kw_if
  | Kw_else
  | Kw_while
  | Kw_for
  | Kw_in
  | Kw_break
  | Kw_continue
  | Kw_repeat (* EX1: `repeat { … } while cond` *)
  (* arithmetic *)
  | Plus
  | Minus
  | Star
  | Slash
  | Percent
  (* assignment / comparison *)
  | Eq
  | EqEq
  | Ne
  | Lt
  | Le
  | Gt
  | Ge
  (* logical (NEW) *)
  | AmpAmp (* && *)
  | PipePipe (* || *)
  (* range (NEW) *)
  | DotDotLt (* ..< *)
  | DotDotDot (* ... — EX2: the CLOSED range, inclusive of its upper bound *)
  (* punctuation *)
  | Colon
  | LParen
  | RParen
  | LBrace (* { NEW *)
  | RBrace (* } NEW *)
  | Comma
  (* structural *)
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
  | Kw_as -> "as"
  | Kw_if -> "if"
  | Kw_else -> "else"
  | Kw_while -> "while"
  | Kw_for -> "for"
  | Kw_in -> "in"
  | Kw_break -> "break"
  | Kw_continue -> "continue"
  | Kw_repeat -> "repeat"
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
  | DotDotDot -> "..."
  | Colon -> ":"
  | LParen -> "("
  | RParen -> ")"
  | LBrace -> "{"
  | RBrace -> "}"
  | Comma -> ","
  | Newline -> "newline"
  | Eof -> "eof"

let keyword_or_ident (text : string) : kind =
  match text with
  | "let" -> Kw_let
  | "var" -> Kw_var
  | "true" -> Kw_true
  | "false" -> Kw_false
  | "as" -> Kw_as
  | "if" -> Kw_if
  | "else" -> Kw_else
  | "while" -> Kw_while
  | "for" -> Kw_for
  | "in" -> Kw_in
  | "break" -> Kw_break
  | "continue" -> Kw_continue
  | "repeat" -> Kw_repeat
  | _ -> Ident text
