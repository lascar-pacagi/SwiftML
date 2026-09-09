(* ANSWER KEY — concept 10 lexer.  Carries the Phase-2 scanner and adds the punctuation
   used by structs: member access `.` and `;` as a statement separator. *)

type t = {
  source : string;
  len : int;
  mutable pos : int;
  mutable line : int;
  mutable col : int;
  diagnostics : Diagnostics.sink; (* errors are REPORTED, not raised — see [report_error] below *)
}

let create (source : string) (diagnostics : Diagnostics.sink) : t =
  { source; len = String.length source; pos = 0; line = 1; col = 1; diagnostics }
let current_position (lexer : t) : Token.pos = { Token.line = lexer.line; col = lexer.col; offset = lexer.pos }
let at_end (lexer : t) : bool = lexer.pos >= lexer.len
let peek_char (lexer : t) : char = if at_end lexer then '\000' else lexer.source.[lexer.pos]
let peek_next_char (lexer : t) : char = if lexer.pos + 1 < lexer.len then lexer.source.[lexer.pos + 1] else '\000'

let advance_char (lexer : t) : char =
  let character = lexer.source.[lexer.pos] in
  lexer.pos <- lexer.pos + 1;
  (if character = '\n' then (
     lexer.line <- lexer.line + 1;
     lexer.col <- 1)
   else lexer.col <- lexer.col + 1);
  character

let make_token (start_position : Token.pos) (lexer : t) (kind : Token.kind) : Token.t =
  { Token.kind; span = { Token.lo = start_position; hi = current_position lexer } }

(* Report at [start_position .. current_position] and KEEP LEXING, like `Lexer::diagnose` in
   swift/lib/Parse/Lexer.cpp. Recovery is the point: one run reports every bad byte. *)
let report_error (lexer : t) (start_position : Token.pos) (message : string) : unit =
  Diagnostics.error lexer.diagnostics { Token.lo = start_position; hi = current_position lexer } message

let is_digit character = character >= '0' && character <= '9'
let is_identifier_start character =
  (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || character = '_'

let is_identifier_continue character = is_identifier_start character || is_digit character

(* scan a "..." string literal (the opening '"' is at the cursor); basic escapes *)
let scan_string (lexer : t) : string =
  ignore (advance_char lexer (* opening quote *));
  let buffer = Buffer.create 16 in
  let rec loop () =
    if at_end lexer || peek_char lexer = '"' then ()
    else
      let character = advance_char lexer in
      if character = '\\' && not (at_end lexer) then (
        (match advance_char lexer with
        | 'n' -> Buffer.add_char buffer '\n'
        | 't' -> Buffer.add_char buffer '\t'
        | '"' -> Buffer.add_char buffer '"'
        | '\\' -> Buffer.add_char buffer '\\'
        | other -> Buffer.add_char buffer other);
        loop ())
      else (Buffer.add_char buffer character; loop ())
  in
  loop ();
  if not (at_end lexer) then ignore (advance_char lexer (* closing quote *));
  Buffer.contents buffer

let rec next (lexer : t) : Token.t =
  (* trivia (given, Phase 1) *)
  let rec skip_trivia () =
    if at_end lexer then ()
    else
      let character = peek_char lexer in
      if character = ' ' || character = '\t' || character = '\r' then (ignore (advance_char lexer); skip_trivia ())
      else if character = '/' && peek_next_char lexer = '/' then (
        ignore (advance_char lexer); ignore (advance_char lexer);
        while (not (at_end lexer)) && peek_char lexer <> '\n' do ignore (advance_char lexer) done;
        skip_trivia ())
      else if character = '/' && peek_next_char lexer = '*' then (
        ignore (advance_char lexer); ignore (advance_char lexer);
        let depth = ref 1 in
        while !depth > 0 && not (at_end lexer) do
          if peek_char lexer = '/' && peek_next_char lexer = '*' then (ignore (advance_char lexer); ignore (advance_char lexer); incr depth)
          else if peek_char lexer = '*' && peek_next_char lexer = '/' then (ignore (advance_char lexer); ignore (advance_char lexer); decr depth)
          else ignore (advance_char lexer)
        done;
        (* swiftc's `diag::lex_unterminated_block_comment`, reported at end of input *)
        if !depth > 0 then report_error lexer (current_position lexer) "unterminated '/*' comment";
        skip_trivia ())
      else ()
  in
  skip_trivia ();
  let start_position = current_position lexer in
  if at_end lexer then make_token start_position lexer Token.Eof
  else
    let character = peek_char lexer in
    if is_digit character then (
      (* number: integer part, then an optional fractional part => Double *)
      let start_offset = lexer.pos in
      while (not (at_end lexer)) && is_digit (peek_char lexer) do ignore (advance_char lexer) done;
      if peek_char lexer = '.' && is_digit (peek_next_char lexer) then (
        ignore (advance_char lexer (* '.' *));
        while (not (at_end lexer)) && is_digit (peek_char lexer) do ignore (advance_char lexer) done;
        make_token start_position lexer (Token.Float (float_of_string (String.sub lexer.source start_offset (lexer.pos - start_offset)))))
      else make_token start_position lexer (Token.Int (int_of_string (String.sub lexer.source start_offset (lexer.pos - start_offset)))))
    else if character = '"' then make_token start_position lexer (Token.String (scan_string lexer))
    else if is_identifier_start character then (
      let start_offset = lexer.pos in
      while (not (at_end lexer)) && is_identifier_continue (peek_char lexer) do ignore (advance_char lexer) done;
      make_token start_position lexer (Token.keyword_or_ident (String.sub lexer.source start_offset (lexer.pos - start_offset))))
    else
      match character with
      | '+' -> ignore (advance_char lexer); make_token start_position lexer Token.Plus
      | '-' ->
          ignore (advance_char lexer);
          if peek_char lexer = '>' then (ignore (advance_char lexer); make_token start_position lexer Token.Arrow)
          else make_token start_position lexer Token.Minus
      | '*' -> ignore (advance_char lexer); make_token start_position lexer Token.Star
      | '/' -> ignore (advance_char lexer); make_token start_position lexer Token.Slash
      | '%' -> ignore (advance_char lexer); make_token start_position lexer Token.Percent
      | '=' ->
          ignore (advance_char lexer);
          if peek_char lexer = '=' then (ignore (advance_char lexer); make_token start_position lexer Token.EqEq) else make_token start_position lexer Token.Eq
      | '!' ->
          ignore (advance_char lexer);
          if peek_char lexer = '=' then (ignore (advance_char lexer); make_token start_position lexer Token.Ne)
          else (report_error lexer start_position "expected '=' after '!'"; next lexer)
      | '<' ->
          ignore (advance_char lexer);
          if peek_char lexer = '=' then (ignore (advance_char lexer); make_token start_position lexer Token.Le) else make_token start_position lexer Token.Lt
      | '>' ->
          ignore (advance_char lexer);
          if peek_char lexer = '=' then (ignore (advance_char lexer); make_token start_position lexer Token.Ge) else make_token start_position lexer Token.Gt
      | ':' -> ignore (advance_char lexer); make_token start_position lexer Token.Colon
      | '(' -> ignore (advance_char lexer); make_token start_position lexer Token.LParen
      | ')' -> ignore (advance_char lexer); make_token start_position lexer Token.RParen
      | '{' -> ignore (advance_char lexer); make_token start_position lexer Token.LBrace
      | '}' -> ignore (advance_char lexer); make_token start_position lexer Token.RBrace
      | ',' -> ignore (advance_char lexer); make_token start_position lexer Token.Comma
      | '&' ->
          ignore (advance_char lexer);
          if peek_char lexer = '&' then (ignore (advance_char lexer); make_token start_position lexer Token.AmpAmp)
          else (report_error lexer start_position "expected '&' after '&'"; next lexer)
      | '|' ->
          ignore (advance_char lexer);
          if peek_char lexer = '|' then (ignore (advance_char lexer); make_token start_position lexer Token.PipePipe)
          else (report_error lexer start_position "expected '|' after '|'"; next lexer)
      | '.' ->
          ignore (advance_char lexer);
          if peek_char lexer = '.' && peek_next_char lexer = '<' then (
            ignore (advance_char lexer);
            ignore (advance_char lexer);
            make_token start_position lexer Token.DotDotLt)
          else make_token start_position lexer Token.Dot (* member access — concept 10 *)
      | '\n' -> ignore (advance_char lexer); make_token start_position lexer Token.Newline
      | ';' -> ignore (advance_char lexer); make_token start_position lexer Token.Newline (* `;` is a statement separator in Swift *)
      | _ ->
          (* swiftc's `diag::lex_invalid_character`; drop the byte and lex on *)
          ignore (advance_char lexer);
          report_error lexer start_position "invalid character in source file";
          next lexer

let tokenize (lexer : t) : Token.t list =
  let rec loop reversed_tokens =
    let token = next lexer in
    match token.Token.kind with Token.Eof -> List.rev (token :: reversed_tokens) | _ -> loop (token :: reversed_tokens)
  in
  loop []
