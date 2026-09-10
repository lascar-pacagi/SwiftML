(* The lexer: turn a source string into a stream of [Token.t].

   Hand-written (char cursor + token DFA), mirroring:
     swift/lib/Parse/Lexer.cpp     (Lexer::lexImpl and friends)

   >>> You build this in concept  phase1-minimal/01-lexer. <<<
   The token type (token.ml) is the contract; current_position you produce it. [tokenize] is
   provided (it just drives [next]); the lesson is implementing [next]. *)

type t = {
  source : string;
  len : int;
  mutable pos : int; (* byte offset of the next unread char *)
  mutable line : int;
  mutable col : int;
  diagnostics : Diagnostics.sink; (* where errors go — see [report_error] below *)
}

let create (source : string) (diagnostics : Diagnostics.sink) : t =
  { source; len = String.length source; pos = 0; line = 1; col = 1; diagnostics }

(* --- small cursor helpers you'll want (already written) --------------------- *)

let current_position (lexer : t) : Token.pos = { Token.line = lexer.line; col = lexer.col; offset = lexer.pos }
let at_end (lexer : t) : bool = lexer.pos >= lexer.len
let peek_char (lexer : t) : char = if at_end lexer then '\000' else lexer.source.[lexer.pos]

(* Advance one char, maintaining line/col. Returns the consumed char. *)
let advance_char (lexer : t) : char =
  let c = lexer.source.[lexer.pos] in
  lexer.pos <- lexer.pos + 1;
  (if c = '\n' then (
     lexer.line <- lexer.line + 1;
     lexer.col <- 1)
   else lexer.col <- lexer.col + 1);
  c

let make_token (lo : Token.pos) (lexer : t) (kind : Token.kind) : Token.t =
  { Token.kind; span = { Token.lo; hi = current_position lexer } }

(* Report an error at [lo .. current_position], then KEEP LEXING. Mirrors `Lexer::diagnose` in
   swift/lib/Parse/Lexer.cpp (its `Lexer` takes a `DiagnosticEngine *` for exactly this;
   Lexer.cpp calls `diagnose` in 59 places). Recovery is the point: one run should report
   every bad byte in the file, not die on the first. *)
let report_error (lexer : t) (lo : Token.pos) (msg : string) : unit =
  Diagnostics.error lexer.diagnostics { Token.lo; hi = current_position lexer } msg

(* --- the part you implement ------------------------------------------------- *)

(* Produce the next token: skip trivia, then scan one token starting at the cursor.

   The contract the tests hold you to: trivia is spaces/tabs/CR and //, /* */ comments
   (which NEST); a newline is a TOKEN, not trivia; a token's span starts at the token,
   not at the trivia before it; and a problem is REPORTED with [report_error] and recovered
   from, never raised.

   Walk-through, if you want one: explainer §3. *)
let next (lexer : t) : Token.t =
  ignore (current_position, make_token, advance_char, peek_char, at_end, lexer);
  failwith "TODO(01-lexer): implement Lexer.next (the scanning DFA)"

(* Drive [next] to the end. Provided — you only implement [next]. *)
let tokenize (lexer : t) : Token.t list =
  let rec loop acc =
    let tok = next lexer in
    match tok.Token.kind with Token.Eof -> List.rev (tok :: acc) | _ -> loop (tok :: acc)
  in
  loop []
