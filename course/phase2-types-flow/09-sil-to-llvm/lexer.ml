(* FROZEN SOLUTION — concept 07 lexer (carries 05–06; adds the '->' arrow). Phase-1 scanning + the Phase-2 lexemes:
   string/float literals, the `:` colon, and the comparison operators. Verify by copying
   over ../lexer.ml and running the concept's runtest. *)

type t = {
  src : string;
  len : int;
  mutable pos : int;
  mutable line : int;
  mutable col : int;
  diags : Diagnostics.sink; (* errors are REPORTED, not raised — see [error] below *)
}

let create (src : string) (diags : Diagnostics.sink) : t =
  { src; len = String.length src; pos = 0; line = 1; col = 1; diags }
let here (lx : t) : Token.pos = { Token.line = lx.line; col = lx.col; offset = lx.pos }
let at_end (lx : t) : bool = lx.pos >= lx.len
let peek_char (lx : t) : char = if at_end lx then '\000' else lx.src.[lx.pos]
let peek2 (lx : t) : char = if lx.pos + 1 < lx.len then lx.src.[lx.pos + 1] else '\000'

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

(* Report at [lo .. here] and KEEP LEXING, like `Lexer::diagnose` in
   swift/lib/Parse/Lexer.cpp. Recovery is the point: one run reports every bad byte. *)
let error (lx : t) (lo : Token.pos) (msg : string) : unit =
  Diagnostics.error lx.diags { Token.lo; hi = here lx } msg

let is_digit c = c >= '0' && c <= '9'
let is_ident_head c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
let is_ident_cont c = is_ident_head c || is_digit c

(* scan a "..." string literal (the opening '"' is at the cursor); basic escapes *)
let scan_string (lx : t) : string =
  ignore (bump lx (* opening quote *));
  let b = Buffer.create 16 in
  let rec loop () =
    if at_end lx || peek_char lx = '"' then ()
    else
      let c = bump lx in
      if c = '\\' && not (at_end lx) then (
        (match bump lx with
        | 'n' -> Buffer.add_char b '\n'
        | 't' -> Buffer.add_char b '\t'
        | '"' -> Buffer.add_char b '"'
        | '\\' -> Buffer.add_char b '\\'
        | other -> Buffer.add_char b other);
        loop ())
      else (Buffer.add_char b c; loop ())
  in
  loop ();
  if not (at_end lx) then ignore (bump lx (* closing quote *));
  Buffer.contents b

let rec next (lx : t) : Token.t =
  (* trivia (given, Phase 1) *)
  let rec skip_trivia () =
    if at_end lx then ()
    else
      let c = peek_char lx in
      if c = ' ' || c = '\t' || c = '\r' then (ignore (bump lx); skip_trivia ())
      else if c = '/' && peek2 lx = '/' then (
        ignore (bump lx); ignore (bump lx);
        while (not (at_end lx)) && peek_char lx <> '\n' do ignore (bump lx) done;
        skip_trivia ())
      else if c = '/' && peek2 lx = '*' then (
        ignore (bump lx); ignore (bump lx);
        let depth = ref 1 in
        while !depth > 0 && not (at_end lx) do
          if peek_char lx = '/' && peek2 lx = '*' then (ignore (bump lx); ignore (bump lx); incr depth)
          else if peek_char lx = '*' && peek2 lx = '/' then (ignore (bump lx); ignore (bump lx); decr depth)
          else ignore (bump lx)
        done;
        (* swiftc's `diag::lex_unterminated_block_comment`, reported at end of input *)
        if !depth > 0 then error lx (here lx) "unterminated '/*' comment";
        skip_trivia ())
      else ()
  in
  skip_trivia ();
  let lo = here lx in
  if at_end lx then make lo lx Token.Eof
  else
    let c = peek_char lx in
    if is_digit c then (
      (* number: integer part, then an optional fractional part => Double *)
      let start = lx.pos in
      while (not (at_end lx)) && is_digit (peek_char lx) do ignore (bump lx) done;
      if peek_char lx = '.' && is_digit (peek2 lx) then (
        ignore (bump lx (* '.' *));
        while (not (at_end lx)) && is_digit (peek_char lx) do ignore (bump lx) done;
        make lo lx (Token.Float (float_of_string (String.sub lx.src start (lx.pos - start)))))
      else make lo lx (Token.Int (int_of_string (String.sub lx.src start (lx.pos - start)))))
    else if c = '"' then make lo lx (Token.String (scan_string lx))
    else if is_ident_head c then (
      let start = lx.pos in
      while (not (at_end lx)) && is_ident_cont (peek_char lx) do ignore (bump lx) done;
      make lo lx (Token.keyword_or_ident (String.sub lx.src start (lx.pos - start))))
    else
      match c with
      | '+' -> ignore (bump lx); make lo lx Token.Plus
      | '-' ->
          ignore (bump lx);
          if peek_char lx = '>' then (ignore (bump lx); make lo lx Token.Arrow)
          else make lo lx Token.Minus
      | '*' -> ignore (bump lx); make lo lx Token.Star
      | '/' -> ignore (bump lx); make lo lx Token.Slash
      | '%' -> ignore (bump lx); make lo lx Token.Percent
      | '=' ->
          ignore (bump lx);
          if peek_char lx = '=' then (ignore (bump lx); make lo lx Token.EqEq) else make lo lx Token.Eq
      | '!' ->
          ignore (bump lx);
          if peek_char lx = '=' then (ignore (bump lx); make lo lx Token.Ne)
          else (error lx lo "expected '=' after '!'"; next lx)
      | '<' ->
          ignore (bump lx);
          if peek_char lx = '=' then (ignore (bump lx); make lo lx Token.Le) else make lo lx Token.Lt
      | '>' ->
          ignore (bump lx);
          if peek_char lx = '=' then (ignore (bump lx); make lo lx Token.Ge) else make lo lx Token.Gt
      | ':' -> ignore (bump lx); make lo lx Token.Colon
      | '(' -> ignore (bump lx); make lo lx Token.LParen
      | ')' -> ignore (bump lx); make lo lx Token.RParen
      | '{' -> ignore (bump lx); make lo lx Token.LBrace
      | '}' -> ignore (bump lx); make lo lx Token.RBrace
      | ',' -> ignore (bump lx); make lo lx Token.Comma
      | '&' ->
          ignore (bump lx);
          if peek_char lx = '&' then (ignore (bump lx); make lo lx Token.AmpAmp)
          else (error lx lo "expected '&' after '&'"; next lx)
      | '|' ->
          ignore (bump lx);
          if peek_char lx = '|' then (ignore (bump lx); make lo lx Token.PipePipe)
          else (error lx lo "expected '|' after '|'"; next lx)
      | '.' ->
          ignore (bump lx);
          if peek_char lx = '.' && peek2 lx = '<' then (
            ignore (bump lx);
            ignore (bump lx);
            make lo lx Token.DotDotLt)
          else (error lx lo "unexpected character '.'"; next lx)
      | '\n' -> ignore (bump lx); make lo lx Token.Newline
      | _ ->
          (* swiftc's `diag::lex_invalid_character`; drop the byte and lex on *)
          ignore (bump lx);
          error lx lo "invalid character in source file";
          next lx

let tokenize (lx : t) : Token.t list =
  let rec loop acc =
    let tok = next lx in
    match tok.Token.kind with Token.Eof -> List.rev (tok :: acc) | _ -> loop (tok :: acc)
  in
  loop []
