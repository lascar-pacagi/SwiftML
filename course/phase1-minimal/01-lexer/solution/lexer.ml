(* FROZEN SOLUTION — concept 01-lexer. The verified answer key for [lexer.ml].
   Kept out of the build by `(dirs :standard \ solution)`; it is a drop-in copy of
   the stage module with [next] implemented. Verify by copying over ../lexer.ml and
   running `dune build @phase1-minimal/01-lexer/runtest`.

   Hand-written (char cursor + token DFA), mirroring:
     swift/lib/Parse/Lexer.cpp     (Lexer::lexImpl and friends) *)

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

(* --- small cursor helpers --------------------------------------------------- *)

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

(* Look one char past the cursor (or '\000' past end) — for the two-char lookahead
   the comment forms need: `//`, `/*`, `*/`. *)
let peek_next_char (lexer : t) : char = if lexer.pos + 1 < lexer.len then lexer.source.[lexer.pos + 1] else '\000'

(* Swift identifier/number character classes (ASCII subset for Phase 1; Unicode
   identifiers come later). Mirrors the predicates in swift/lib/Parse/Lexer.cpp. *)
let is_digit (c : char) : bool = c >= '0' && c <= '9'

let is_identifier_start (c : char) : bool =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'

let is_identifier_continue (c : char) : bool = is_identifier_start c || is_digit c

(* --- the scanning DFA ------------------------------------------------------- *)

let rec next (lexer : t) : Token.t =
  (* 1. Skip trivia: non-newline whitespace and //, /* */ comments. Loop, because a
     comment can be followed by more whitespace/comments. Newlines are NOT trivia. *)
  let rec skip_trivia () =
    if at_end lexer then ()
    else
      let c = peek_char lexer in
      if c = ' ' || c = '\t' || c = '\r' then (
        ignore (advance_char lexer);
        skip_trivia ())
      else if c = '/' && peek_next_char lexer = '/' then (
        (* line comment: consume to end of line, but leave the '\n' (it's a token). *)
        ignore (advance_char lexer);
        ignore (advance_char lexer);
        while (not (at_end lexer)) && peek_char lexer <> '\n' do
          ignore (advance_char lexer)
        done;
        skip_trivia ())
      else if c = '/' && peek_next_char lexer = '*' then (
        (* block comment: nests, unlike C. Track depth until it returns to 0. *)
        ignore (advance_char lexer);
        ignore (advance_char lexer);
        let depth = ref 1 in
        while !depth > 0 && not (at_end lexer) do
          if peek_char lexer = '/' && peek_next_char lexer = '*' then (
            ignore (advance_char lexer);
            ignore (advance_char lexer);
            incr depth)
          else if peek_char lexer = '*' && peek_next_char lexer = '/' then (
            ignore (advance_char lexer);
            ignore (advance_char lexer);
            decr depth)
          else ignore (advance_char lexer)
        done;
        (* [depth > 0] means the comment was never closed. Same wording and same position
           as swiftc (`diag::lex_unterminated_block_comment`, reported at end-of-file); we
           then carry on and finish with Eof. Exercise 2 adds the NOTE swiftc also emits,
           pointing back at the opener. *)
        if !depth > 0 then report_error lexer (current_position lexer) "unterminated '/*' comment";
        skip_trivia ())
      else ()
  in
  skip_trivia ();
  (* 2. Capture the start position of the token we're about to scan. *)
  let lo = current_position lexer in
  (* 3. End of input. *)
  if at_end lexer then make_token lo lexer Token.Eof
  else
    let c = peek_char lexer in
    (* 4. Dispatch on the first significant character. *)
    if is_digit c then (
      (* integer literal — maximal munch over the run of digits *)
      let start = lexer.pos in
      while (not (at_end lexer)) && is_digit (peek_char lexer) do
        ignore (advance_char lexer)
      done;
      let n = int_of_string (String.sub lexer.source start (lexer.pos - start)) in
      make_token lo lexer (Token.Int n))
    else if is_identifier_start c then (
      (* identifier — head then run of ident chars; then the keyword table *)
      let start = lexer.pos in
      while (not (at_end lexer)) && is_identifier_continue (peek_char lexer) do
        ignore (advance_char lexer)
      done;
      let text = String.sub lexer.source start (lexer.pos - start) in
      make_token lo lexer (Token.keyword_or_ident text))
    else
      (* single-character operators, punctuation, and the significant newline *)
      match c with
      | '+' ->
          ignore (advance_char lexer);
          make_token lo lexer Token.Plus
      | '-' ->
          ignore (advance_char lexer);
          make_token lo lexer Token.Minus
      | '*' ->
          ignore (advance_char lexer);
          make_token lo lexer Token.Star
      | '/' ->
          ignore (advance_char lexer);
          make_token lo lexer Token.Slash
      | '%' ->
          ignore (advance_char lexer);
          make_token lo lexer Token.Percent
      | '=' ->
          ignore (advance_char lexer);
          make_token lo lexer Token.Eq
      | '(' ->
          ignore (advance_char lexer);
          make_token lo lexer Token.LParen
      | ')' ->
          ignore (advance_char lexer);
          make_token lo lexer Token.RParen
      | ',' ->
          ignore (advance_char lexer);
          make_token lo lexer Token.Comma
      | '\n' ->
          ignore (advance_char lexer);
          make_token lo lexer Token.Newline
      | _ ->
          (* swiftc's `diag::lex_invalid_character` — and, like swiftc, we RECOVER: drop the
             byte and lex on, so one run reports every bad character in the file rather than
             dying on the first. *)
          ignore (advance_char lexer);
          report_error lexer lo "invalid character in source file";
          next lexer

(* Drive [next] to the end. *)
let tokenize (lexer : t) : Token.t list =
  let rec loop acc =
    let tok = next lexer in
    match tok.Token.kind with Token.Eof -> List.rev (tok :: acc) | _ -> loop (tok :: acc)
  in
  loop []
