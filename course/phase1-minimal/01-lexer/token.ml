(* Tokens for the Phase-1 subset. This type grows every phase (string/float
   literals, more keywords, more operators, attributes, …).

   Design oracle:
     swift/include/swift/Parse/Token.h     (the Token class)
     swift/include/swift/Syntax/TokenKinds.def  (the master list of token kinds)
     swift/lib/Parse/Lexer.cpp              (how they are produced)

   This file is a *contract*: it is fully written, not a skeleton. The lexer
   (lexer.ml) is what you implement to produce these. *)

(* A source position. `offset` is the 0-based byte index; line/col are 1-based. *)
type pos = { line : int; col : int; offset : int }

(* A half-open source range [lo, hi). *)
type span = { lo : pos; hi : pos }

let dummy_pos = { line = 0; col = 0; offset = 0 }
let dummy_span = { lo = dummy_pos; hi = dummy_pos }

type kind =
  (* literals *)
  | Int of int (* 123 — Phase 1: decimal Int only *)
  (* identifiers & keywords *)
  | Ident of string (* foo, print (print is just an identifier in Swift) *)
  | Kw_let
  | Kw_var
  (* operators *)
  | Plus
  | Minus
  | Star
  | Slash
  | Percent
  | Eq (* = *)
  (* punctuation *)
  | LParen
  | RParen
  | Comma
  (* structural *)
  | Newline (* Swift terminates statements at newlines *)
  | Eof

type t = { kind : kind; span : span }

(* Human-readable kind, used by `swiftml --emit-tokens` and in test output. *)
let string_of_kind = function
  | Int n -> Printf.sprintf "int(%d)" n
  | Ident s -> Printf.sprintf "ident(%s)" s
  | Kw_let -> "let"
  | Kw_var -> "var"
  | Plus -> "+"
  | Minus -> "-"
  | Star -> "*"
  | Slash -> "/"
  | Percent -> "%"
  | Eq -> "="
  | LParen -> "("
  | RParen -> ")"
  | Comma -> ","
  | Newline -> "newline"
  | Eof -> "eof"

(* Map an identifier spelling to a keyword kind, or keep it an identifier.
   Grows as the language does. *)
let keyword_or_ident (s : string) : kind =
  match s with "let" -> Kw_let | "var" -> Kw_var | _ -> Ident s
