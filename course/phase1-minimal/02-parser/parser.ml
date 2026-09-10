(* The parser: turn a token stream into an [Ast.program].

   Hand-written recursive descent (statements) + Pratt / precedence climbing
   (expressions), mirroring:
     swift/lib/Parse/Parser.cpp      (the cursor + expect/consume helpers)
     swift/lib/Parse/ParseStmt.cpp   (statement dispatch)
     swift/lib/Parse/ParseExpr.cpp   (parseExprSequence — Swift's precedence folding)

   >>> You build this in concept  phase1-minimal/02-parser. <<<
   The cursor helpers, the binding-power table and the two small span/identifier
   helpers are given; you write the three functions marked TODO(02...). See the
   explainer §3 for a step-by-step walk-through, §2 for why Pratt parsing works. *)

type t = {
  tokens : Token.t array;
  mutable pos : int;
  diagnostics : Diagnostics.sink;
}

let create (tokens : Token.t list) (diagnostics : Diagnostics.sink) : t =
  { tokens = Array.of_list tokens; pos = 0; diagnostics }

(* --- cursor helpers --------------------------------------------------------- *)

let peek (parser : t) : Token.t = parser.tokens.(parser.pos)
let peek_kind (parser : t) : Token.kind = (peek parser).Token.kind

(* One-token lookahead, for distinguishing `c = …` (assignment) from `c + …`. *)
let peek_kind_at (parser : t) (n : int) : Token.kind =
  let i = parser.pos + n in
  if i < Array.length parser.tokens then parser.tokens.(i).Token.kind
  else Token.Eof

let advance (parser : t) : Token.t =
  let token = parser.tokens.(parser.pos) in
  if parser.pos < Array.length parser.tokens - 1 then
    parser.pos <- parser.pos + 1;
  token

(* Consume a token of the expected kind, or report an error and return the current one. *)
let expect (parser : t) (k : Token.kind) (description : string) : Token.t =
  let token = peek parser in
  if token.Token.kind = k then advance parser
  else (
    Diagnostics.error parser.diagnostics token.Token.span
      (Printf.sprintf "expected %s" description);
    token)

(* Pratt binding powers: higher binds tighter. (Phase 1 levels.) *)
let infix_bp : Token.kind -> int option = function
  | Token.Plus | Token.Minus -> Some 10
  | Token.Star | Token.Slash | Token.Percent -> Some 20
  | _ -> None

let binop_of_kind : Token.kind -> Ast.binop option = function
  | Token.Plus -> Some Ast.Add
  | Token.Minus -> Some Ast.Sub
  | Token.Star -> Some Ast.Mul
  | Token.Slash -> Some Ast.Div
  | Token.Percent -> Some Ast.Mod
  | _ -> None

(* Unary minus binds tighter than any binary operator. *)
let unary_bp = 100

let span_between (lo : Token.span) (hi : Token.span) : Token.span =
  { Token.lo = lo.Token.lo; hi = hi.Token.hi }

(* --- expressions: Pratt parser --------------------------------------------- *)

let rec parse_expr_bp (parser : t) (minimum_binding_power : int) : Ast.expr =
  (* TODO(02a): parse one expression, absorbing only operators whose binding power is
     >= [minimum_binding_power]. Parse a prefix (literal, variable, call,
     parenthesized expression, or unary minus), then
     the infix fold. Report a missing expression rather than raising, and keep parsing.
     Walk-through: explainer §3.1-2. *)
  ignore (parser, minimum_binding_power, parse_call_args);
  failwith "TODO(02a): implement Parser.parse_expr_bp (the Pratt loop)"

(* Zero-or-more comma-separated arguments, up to the closing ')'. *)
and parse_call_args (parser : t) : Ast.expr list =
  (* TODO(02a): zero or more expressions separated by ',', in source order. *)
  ignore parser;
  failwith "TODO(02a): implement Parser.parse_call_args"

let parse_expr (parser : t) : Ast.expr = parse_expr_bp parser 0

(* --- statements ------------------------------------------------------------- *)

(* Extract an identifier spelling, or report and recover with "_". *)
let parse_ident (parser : t) (description : string) : string * Token.span =
  match peek_kind parser with
  | Token.Ident s ->
      let t = advance parser in
      (s, t.Token.span)
  | _ ->
      let t = peek parser in
      Diagnostics.error parser.diagnostics t.Token.span
        (Printf.sprintf "expected %s" description);
      ("_", t.Token.span)

let parse_stmt (parser : t) : Ast.stmt =
  (* TODO(02b): one statement — a `let`/`var` binding, a reassignment, or a bare
     expression. Explainer §3.3 (note which case needs a token of lookahead). *)
  ignore parser;
  failwith "TODO(02b): implement Parser.parse_stmt"

(* Whole file: skip blank lines, parse statements until Eof, consuming the Newline
   (or Eof) that terminates each. *)
let parse_program (parser : t) : Ast.program =
  (* TODO(02c): every statement in the file, in source order, each terminated by a
     newline (or Eof). Blank lines are not statements. Explainer §3.4. *)
  ignore parser;
  failwith "TODO(02c): implement Parser.parse_program"
