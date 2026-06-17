(* FROZEN SOLUTION — concept 01-lexer. The verified answer key for [lexer.ml].
   Kept out of the build by `(dirs :standard \ solution)`; it is a drop-in copy of
   the stage module with [next] implemented. Verify by copying over ../lexer.ml and
   running `dune build @phase1-minimal/01-lexer/runtest`.

   Hand-written (char cursor + token DFA), mirroring:
     swift/lib/Parse/Lexer.cpp     (Lexer::lexImpl and friends) *)

type t = {
  src : string;
  len : int;
  mutable pos : int; (* byte offset of the next unread char *)
  mutable line : int;
  mutable col : int;
}

let create (src : string) : t = { src; len = String.length src; pos = 0; line = 1; col = 1 }

(* --- small cursor helpers --------------------------------------------------- *)

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

(* Look one char past the cursor (or '\000' past end) — for the two-char lookahead
   the comment forms need: `//`, `/*`, `*/`. *)
let peek2 (lx : t) : char = if lx.pos + 1 < lx.len then lx.src.[lx.pos + 1] else '\000'

(* Swift identifier/number character classes (ASCII subset for Phase 1; Unicode
   identifiers come later). Mirrors the predicates in swift/lib/Parse/Lexer.cpp. *)
let is_digit (c : char) : bool = c >= '0' && c <= '9'

let is_ident_head (c : char) : bool =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'

let is_ident_cont (c : char) : bool = is_ident_head c || is_digit c

(* --- the scanning DFA ------------------------------------------------------- *)

let next (lx : t) : Token.t =
  (* 1. Skip trivia: non-newline whitespace and //, /* */ comments. Loop, because a
     comment can be followed by more whitespace/comments. Newlines are NOT trivia. *)
  let rec skip_trivia () =
    if at_end lx then ()
    else
      let c = peek_char lx in
      if c = ' ' || c = '\t' || c = '\r' then (
        ignore (bump lx);
        skip_trivia ())
      else if c = '/' && peek2 lx = '/' then (
        (* line comment: consume to end of line, but leave the '\n' (it's a token). *)
        ignore (bump lx);
        ignore (bump lx);
        while (not (at_end lx)) && peek_char lx <> '\n' do
          ignore (bump lx)
        done;
        skip_trivia ())
      else if c = '/' && peek2 lx = '*' then (
        (* block comment: nests, unlike C. Track depth until it returns to 0. *)
        ignore (bump lx);
        ignore (bump lx);
        let depth = ref 1 in
        while !depth > 0 && not (at_end lx) do
          if peek_char lx = '/' && peek2 lx = '*' then (
            ignore (bump lx);
            ignore (bump lx);
            incr depth)
          else if peek_char lx = '*' && peek2 lx = '/' then (
            ignore (bump lx);
            ignore (bump lx);
            decr depth)
          else ignore (bump lx)
        done;
        (* If [depth > 0] here the comment was unterminated; the Phase-1 lexer has no
           diagnostics sink, so we stop silently. (Exercise 2 adds a real diagnostic.) *)
        skip_trivia ())
      else ()
  in
  skip_trivia ();
  (* 2. Capture the start position of the token we're about to scan. *)
  let lo = here lx in
  (* 3. End of input. *)
  if at_end lx then make lo lx Token.Eof
  else
    let c = peek_char lx in
    (* 4. Dispatch on the first significant character. *)
    if is_digit c then (
      (* integer literal — maximal munch over the run of digits *)
      let start = lx.pos in
      while (not (at_end lx)) && is_digit (peek_char lx) do
        ignore (bump lx)
      done;
      let n = int_of_string (String.sub lx.src start (lx.pos - start)) in
      make lo lx (Token.Int n))
    else if is_ident_head c then (
      (* identifier — head then run of ident chars; then the keyword table *)
      let start = lx.pos in
      while (not (at_end lx)) && is_ident_cont (peek_char lx) do
        ignore (bump lx)
      done;
      let text = String.sub lx.src start (lx.pos - start) in
      make lo lx (Token.keyword_or_ident text))
    else
      (* single-character operators, punctuation, and the significant newline *)
      match c with
      | '+' ->
          ignore (bump lx);
          make lo lx Token.Plus
      | '-' ->
          ignore (bump lx);
          make lo lx Token.Minus
      | '*' ->
          ignore (bump lx);
          make lo lx Token.Star
      | '/' ->
          ignore (bump lx);
          make lo lx Token.Slash
      | '%' ->
          ignore (bump lx);
          make lo lx Token.Percent
      | '=' ->
          ignore (bump lx);
          make lo lx Token.Eq
      | '(' ->
          ignore (bump lx);
          make lo lx Token.LParen
      | ')' ->
          ignore (bump lx);
          make lo lx Token.RParen
      | ',' ->
          ignore (bump lx);
          make lo lx Token.Comma
      | '\n' ->
          ignore (bump lx);
          make lo lx Token.Newline
      | _ ->
          (* No diagnostics sink at this stage; a stray character is a hard error. *)
          failwith (Printf.sprintf "lex error %d:%d: unexpected character %C" lx.line lx.col c)

(* Drive [next] to the end. *)
let tokenize (lx : t) : Token.t list =
  let rec loop acc =
    let tok = next lx in
    match tok.Token.kind with Token.Eof -> List.rev (tok :: acc) | _ -> loop (tok :: acc)
  in
  loop []
