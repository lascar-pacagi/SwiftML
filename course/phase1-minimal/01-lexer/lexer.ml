(* The lexer: turn a source string into a stream of [Token.t].

   Hand-written (char cursor + token DFA), mirroring:
     swift/lib/Parse/Lexer.cpp     (Lexer::lexImpl and friends)

   >>> You build this in concept  phase1-minimal/01-lexer. <<<
   The token type (token.ml) is the contract; here you produce it. [tokenize] is
   provided (it just drives [next]); the lesson is implementing [next]. *)

type t = {
  src : string;
  len : int;
  mutable pos : int; (* byte offset of the next unread char *)
  mutable line : int;
  mutable col : int;
  diags : Diagnostics.sink; (* where errors go — see [error] below *)
}

let create (src : string) (diags : Diagnostics.sink) : t =
  { src; len = String.length src; pos = 0; line = 1; col = 1; diags }

(* --- small cursor helpers you'll want (already written) --------------------- *)

let here (lx : t) : Token.pos = { Token.line = lx.line; col = lx.col; offset = lx.pos }
let at_end (lx : t) : bool = lx.pos >= lx.len
let peek_char (lx : t) : char = if at_end lx then '\000' else lx.src.[lx.pos]

(* Advance one char, maintaining line/col. Returns the consumed char. *)
let bump (lx : t) : char =
  let c = lx.src.[lx.pos] in
  lx.pos <- lx.pos + 1;
  (if c = '\n' then (
     lx.line <- lx.line + 1;
     lx.col <- 1)
   else lx.col <- lx.col + 1);
  c

let make (lo : Token.pos) (lx : t) (kind : Token.kind) : Token.t =
  { Token.kind; span = { Token.lo; hi = here lx } }

(* Report an error at [lo .. here], then KEEP LEXING. Mirrors `Lexer::diagnose` in
   swift/lib/Parse/Lexer.cpp (its `Lexer` takes a `DiagnosticEngine *` for exactly this;
   Lexer.cpp calls `diagnose` in 59 places). Recovery is the point: one run should report
   every bad byte in the file, not die on the first. *)
let error (lx : t) (lo : Token.pos) (msg : string) : unit =
  Diagnostics.error lx.diags { Token.lo; hi = here lx } msg

(* --- the part you implement ------------------------------------------------- *)

(* Produce the next token. The scanning DFA, in order:
     1. skip whitespace that is NOT a newline (newlines are significant tokens);
     2. skip // line comments and /* ... */ block comments (block comments nest in Swift);
     3. if at end of input, return [Eof];
     4. otherwise dispatch on [peek_char lx]:
          - digit            -> scan an integer literal      (Token.Int)
          - letter or '_'    -> scan an identifier, then     (Token.keyword_or_ident)
          - '+' '-' '*' '/' '%' '=' '(' ')' ','
                             -> single-char operator/punct tokens
          - '\n'             -> Token.Newline
     Use [here lx] to capture the start position, [bump]/[peek_char]/[at_end] to scan,
     and [make lo lx kind] to build the token with its span.
   Tips: scan the lexeme into a substring with String.sub; convert with int_of_string.
   See the explainer (§3 "Build it") for the full walk-through. *)
let next (lx : t) : Token.t =
  ignore (here, make, bump, peek_char, at_end, lx);
  failwith "TODO(01-lexer): implement Lexer.next (the scanning DFA)"

(* Drive [next] to the end. Provided — you only implement [next]. *)
let tokenize (lx : t) : Token.t list =
  let rec loop acc =
    let tok = next lx in
    match tok.Token.kind with Token.Eof -> List.rev (tok :: acc) | _ -> loop (tok :: acc)
  in
  loop []
