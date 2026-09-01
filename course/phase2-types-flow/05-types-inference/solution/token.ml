(* Tokens for the Phase-2 / concept-05 subset — a *contract* (fully written).

   Carries Phase 1's kinds forward and adds what types need: float & string literals,
   the `true`/`false` keywords, the `:` for annotations, and the comparison operators.
   You produce these in lexer.ml (the Phase-1 scanning is given; you fill the TODO holes
   for the new lexemes).

   Design oracle:
     swift/include/swift/Parse/Token.h
     swift/include/swift/Syntax/TokenKinds.def *)

type pos = { line : int; col : int; offset : int }
type span = { lo : pos; hi : pos }

let dummy_pos = { line = 0; col = 0; offset = 0 }
let dummy_span = { lo = dummy_pos; hi = dummy_pos }

type kind =
  (* literals *)
  | Int of int (* 123 *)
  | Float of float (* 3.14 — a Double literal *)
  | String of string (* "hello" (contents, unescaped) *)
  (* identifiers & keywords *)
  | Ident of string
  | Kw_let
  | Kw_var
  | Kw_true (* NEW: Bool literals are keywords *)
  | Kw_false
  | Kw_as (* NEW: the `e as T` coercion *)
  (* arithmetic operators *)
  | Plus
  | Minus
  | Star
  | Slash
  | Percent
  (* assignment / comparison *)
  | Eq (* =  *)
  | EqEq (* == *)
  | Ne (* != *)
  | Lt (* <  *)
  | Le (* <= *)
  | Gt (* >  *)
  | Ge (* >= *)
  (* punctuation *)
  | Colon (* :  — for type annotations *)
  | LParen
  | RParen
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
  | Colon -> ":"
  | LParen -> "("
  | RParen -> ")"
  | Comma -> ","
  | Newline -> "newline"
  | Eof -> "eof"

(* Identifier spelling -> keyword kind, or a plain identifier. Grows with the language. *)
let keyword_or_ident (s : string) : kind =
  match s with
  | "let" -> Kw_let
  | "var" -> Kw_var
  | "true" -> Kw_true
  | "false" -> Kw_false
  | "as" -> Kw_as
  | _ -> Ident s
