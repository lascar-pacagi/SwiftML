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
  toks : Token.t array;
  mutable pos : int;
  diags : Diagnostics.sink;
}

let create (tokens : Token.t list) (diags : Diagnostics.sink) : t =
  { toks = Array.of_list tokens; pos = 0; diags }

(* --- cursor helpers --------------------------------------------------------- *)

let peek (p : t) : Token.t = p.toks.(p.pos)
let peek_kind (p : t) : Token.kind = (peek p).Token.kind

(* One-token lookahead, for distinguishing `c = …` (assignment) from `c + …`. *)
let peek_kind_at (p : t) (n : int) : Token.kind =
  let i = p.pos + n in
  if i < Array.length p.toks then p.toks.(i).Token.kind else Token.Eof

let advance (p : t) : Token.t =
  let tok = p.toks.(p.pos) in
  if p.pos < Array.length p.toks - 1 then p.pos <- p.pos + 1;
  tok

(* Consume a token of the expected kind, or report an error and return the current one. *)
let expect (p : t) (k : Token.kind) (what : string) : Token.t =
  let tok = peek p in
  if tok.Token.kind = k then advance p
  else (
    Diagnostics.error p.diags tok.Token.span (Printf.sprintf "expected %s" what);
    tok)

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

let rec parse_expr_bp (p : t) (min_bp : int) : Ast.expr =
  (* TODO(02a): parse one expression, absorbing only operators whose binding power is
     >= [min_bp]. A prefix (literal / variable / call / '(' expr ')' / unary minus), then
     the infix fold. Report a missing expression rather than raising, and keep parsing.
     Walk-through: explainer §3.1-2. *)
  ignore (p, min_bp, parse_call_args);
  failwith "TODO(02a): implement Parser.parse_expr_bp (the Pratt loop)"

(* Zero-or-more comma-separated arguments, up to the closing ')'. *)
and parse_call_args (p : t) : Ast.expr list =
  (* TODO(02a): zero or more expressions separated by ',', in source order. *)
  ignore p;
  failwith "TODO(02a): implement Parser.parse_call_args"

let parse_expr (p : t) : Ast.expr = parse_expr_bp p 0

(* --- statements ------------------------------------------------------------- *)

(* Extract an identifier spelling, or report and recover with "_". *)
let parse_ident (p : t) (what : string) : string * Token.span =
  match peek_kind p with
  | Token.Ident s ->
      let t = advance p in
      (s, t.Token.span)
  | _ ->
      let t = peek p in
      Diagnostics.error p.diags t.Token.span (Printf.sprintf "expected %s" what);
      ("_", t.Token.span)

let parse_stmt (p : t) : Ast.stmt =
  (* TODO(02b): one statement — a `let`/`var` binding, a reassignment, or a bare
     expression. Explainer §3.3 (note which case needs a token of lookahead). *)
  ignore p;
  failwith "TODO(02b): implement Parser.parse_stmt"

(* Whole file: skip blank lines, parse statements until Eof, consuming the Newline
   (or Eof) that terminates each. *)
let parse_program (p : t) : Ast.program =
  (* TODO(02c): every statement in the file, in source order, each terminated by a
     newline (or Eof). Blank lines are not statements. Explainer §3.4. *)
  ignore p;
  failwith "TODO(02c): implement Parser.parse_program"
