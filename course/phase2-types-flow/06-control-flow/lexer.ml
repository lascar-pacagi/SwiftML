(* Lexer — concept 06 (skeleton). Concepts 1–05 are filled in; you add the control-flow
   lexemes (the TODO(06) holes): the braces, && / ||, and the ..< range. All mirror 05's
   multi-char '=='/'<='. Reference: solution/lexer.ml. *)

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
  let c = lexer.source.[lexer.pos] in
  lexer.pos <- lexer.pos + 1;
  (if c = '\n' then (
     lexer.line <- lexer.line + 1;
     lexer.col <- 1)
   else lexer.col <- lexer.col + 1);
  c

let make_token (lo : Token.pos) (lexer : t) (kind : Token.kind) : Token.t =
  { Token.kind; span = { Token.lo; hi = current_position lexer } }

(* Report at [lo .. current_position] and KEEP LEXING, like `Lexer::diagnose` in
   swift/lib/Parse/Lexer.cpp. Recovery is the point: one run reports every bad byte. *)
let report_error (lexer : t) (lo : Token.pos) (msg : string) : unit =
  Diagnostics.error lexer.diagnostics { Token.lo; hi = current_position lexer } msg

let is_digit c = c >= '0' && c <= '9'
let is_identifier_start c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
let is_identifier_continue c = is_identifier_start c || is_digit c

(* scan a "..." string literal (the opening quote is at the cursor); basic escapes *)
let scan_string (lexer : t) : string =
  ignore (advance_char lexer (* opening quote *));
  let b = Buffer.create 16 in
  let rec loop () =
    if at_end lexer || peek_char lexer = '"' then ()
    else
      let c = advance_char lexer in
      if c = '\\' && not (at_end lexer) then (
        (match advance_char lexer with
        | 'n' -> Buffer.add_char b '\n'
        | 't' -> Buffer.add_char b '\t'
        | '"' -> Buffer.add_char b '"'
        | '\\' -> Buffer.add_char b '\\'
        | other -> Buffer.add_char b other);
        loop ())
      else (Buffer.add_char b c; loop ())
  in
  loop ();
  if not (at_end lexer) then ignore (advance_char lexer (* closing quote *));
  Buffer.contents b

let rec next (lexer : t) : Token.t =
  (* trivia (given, Phase 1) *)
  let rec skip_trivia () =
    if at_end lexer then ()
    else
      let c = peek_char lexer in
      if c = ' ' || c = '\t' || c = '\r' then (ignore (advance_char lexer); skip_trivia ())
      else if c = '/' && peek_next_char lexer = '/' then (
        ignore (advance_char lexer); ignore (advance_char lexer);
        while (not (at_end lexer)) && peek_char lexer <> '\n' do ignore (advance_char lexer) done;
        skip_trivia ())
      else if c = '/' && peek_next_char lexer = '*' then (
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
  let lo = current_position lexer in
  if at_end lexer then make_token lo lexer Token.Eof
  else
    let c = peek_char lexer in
    if is_digit c then (
      (* number: integer part, then an optional fractional part => Double *)
      let start = lexer.pos in
      while (not (at_end lexer)) && is_digit (peek_char lexer) do ignore (advance_char lexer) done;
      if peek_char lexer = '.' && is_digit (peek_next_char lexer) then (
        ignore (advance_char lexer (* '.' *));
        while (not (at_end lexer)) && is_digit (peek_char lexer) do ignore (advance_char lexer) done;
        make_token lo lexer (Token.Float (float_of_string (String.sub lexer.source start (lexer.pos - start)))))
      else make_token lo lexer (Token.Int (int_of_string (String.sub lexer.source start (lexer.pos - start)))))
    else if c = '"' then make_token lo lexer (Token.String (scan_string lexer))
    else if is_identifier_start c then (
      let start = lexer.pos in
      while (not (at_end lexer)) && is_identifier_continue (peek_char lexer) do ignore (advance_char lexer) done;
      make_token lo lexer (Token.keyword_or_ident (String.sub lexer.source start (lexer.pos - start))))
    else
      match c with
      | '+' -> ignore (advance_char lexer); make_token lo lexer Token.Plus
      | '-' -> ignore (advance_char lexer); make_token lo lexer Token.Minus
      | '*' -> ignore (advance_char lexer); make_token lo lexer Token.Star
      | '/' -> ignore (advance_char lexer); make_token lo lexer Token.Slash
      | '%' -> ignore (advance_char lexer); make_token lo lexer Token.Percent
      | '=' ->
          ignore (advance_char lexer);
          if peek_char lexer = '=' then (ignore (advance_char lexer); make_token lo lexer Token.EqEq) else make_token lo lexer Token.Eq
      | '!' ->
          ignore (advance_char lexer);
          if peek_char lexer = '=' then (ignore (advance_char lexer); make_token lo lexer Token.Ne)
          else (report_error lexer lo "expected '=' after '!'"; next lexer)
      | '<' ->
          ignore (advance_char lexer);
          if peek_char lexer = '=' then (ignore (advance_char lexer); make_token lo lexer Token.Le) else make_token lo lexer Token.Lt
      | '>' ->
          ignore (advance_char lexer);
          if peek_char lexer = '=' then (ignore (advance_char lexer); make_token lo lexer Token.Ge) else make_token lo lexer Token.Gt
      | ':' -> ignore (advance_char lexer); make_token lo lexer Token.Colon
      | '(' -> ignore (advance_char lexer); make_token lo lexer Token.LParen
      | ')' -> ignore (advance_char lexer); make_token lo lexer Token.RParen
      | ',' -> ignore (advance_char lexer); make_token lo lexer Token.Comma
      (* TODO(06): `{ } && || ..<` — maximal munch again; a lone '&', '|' or '.' is an error. *)
      | '\n' -> ignore (advance_char lexer); make_token lo lexer Token.Newline
      | _ ->
          (* swiftc's `diag::lex_invalid_character`; drop the byte and lex on *)
          ignore (advance_char lexer);
          report_error lexer lo "invalid character in source file";
          next lexer

let tokenize (lexer : t) : Token.t list =
  let rec loop acc =
    let tok = next lexer in
    match tok.Token.kind with Token.Eof -> List.rev (tok :: acc) | _ -> loop (tok :: acc)
  in
  loop []
