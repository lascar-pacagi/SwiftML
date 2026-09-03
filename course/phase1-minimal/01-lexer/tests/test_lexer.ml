(* Alcotest unit tests for the lexer (concept 01).

   These call the lexer in-process and assert the exact [Token.kind] list AND source
   spans (line/col/offset) — finer-grained than the cram `--emit-tokens` golden test,
   which only sees the printed kinds and never checks positions.

   The SAME suite runs against both rungs:
     v0       `Lexer`          — the reference scanner (lexer.ml)
     v1_fast  `Lexer_v1_fast`  — the allocation-free rung (lexer_v1_fast.ml), resolved
                                 back to `Token.t list` with `to_tokens`
   plus an equivalence group that pins them token-for-token. A faster lexer that changes
   the token stream is a bug, not a win; `make bench` then checks it is actually faster.

   v1_fast is a SECOND RUNG, not a prerequisite: while `lexer_v1_fast.ml` is still the
   TODO skeleton its groups are skipped, so a learner who only wants v0 gets a green
   `make lab`. Touch that file and all 23 checks switch on automatically.

   RED until you implement `lexer.ml : next`; GREEN against `solution/`.
   Run:  dune build @phase1-minimal/01-lexer/runtest *)

(* A rung lexes a source and returns BOTH halves of the contract: the tokens, and whatever
   the lexer reported into its diagnostics sink. *)
type rung = string -> Token.t list * Diagnostics.t list

let v0 : rung =
 fun src ->
  let d = Diagnostics.create () in
  let toks = Lexer.tokenize (Lexer.create src d) in
  (toks, Diagnostics.all d)

let v1 : rung =
 fun src ->
  let d = Diagnostics.create () in
  let toks = Lexer_v1_fast.to_tokens (Lexer_v1_fast.lex src d) in
  (toks, Diagnostics.all d)

let toks (lex : rung) (src : string) : Token.t list = fst (lex src)

let is_todo (m : string) = String.length m >= 4 && String.sub m 0 4 = "TODO"

let kinds (lex : rung) (src : string) : Token.kind list =
  List.map (fun (t : Token.t) -> t.Token.kind) (toks lex src)

let kind_t =
  Alcotest.testable (fun ppf k -> Format.pp_print_string ppf (Token.string_of_kind k)) ( = )

let token_t =
  Alcotest.testable
    (fun ppf (t : Token.t) ->
      Format.fprintf ppf "%s@%d:%d-%d:%d" (Token.string_of_kind t.Token.kind)
        t.Token.span.Token.lo.Token.line t.Token.span.Token.lo.Token.col
        t.Token.span.Token.hi.Token.line t.Token.span.Token.hi.Token.col)
    ( = )

let check_kinds lex name expected src =
  Alcotest.check (Alcotest.list kind_t) name expected (kinds lex src)

let test_literals_idents lex () =
  check_kinds lex "empty input" [ Token.Eof ] "";
  check_kinds lex "single int" [ Token.Int 1; Token.Eof ] "1";
  check_kinds lex "maximal-munch int" [ Token.Int 123; Token.Eof ] "123";
  check_kinds lex "two ints separated" [ Token.Int 1; Token.Int 2; Token.Eof ] "1 2";
  check_kinds lex "identifier" [ Token.Ident "print"; Token.Eof ] "print";
  check_kinds lex "ident leading _ and digits" [ Token.Ident "_x9"; Token.Eof ] "_x9"

let test_keywords lex () =
  check_kinds lex "let/var are keywords" [ Token.Kw_let; Token.Kw_var; Token.Eof ] "let var";
  (* keyword match is whole-word only — these are identifiers, not keyword + suffix *)
  check_kinds lex "keyword maximal munch"
    [ Token.Ident "lets"; Token.Ident "varx"; Token.Ident "let1"; Token.Ident "_let"; Token.Eof ]
    "lets varx let1 _let"

let test_operators lex () =
  check_kinds lex "all operators and punctuation"
    [
      Token.Plus; Token.Minus; Token.Star; Token.Slash; Token.Percent; Token.Eq; Token.LParen;
      Token.RParen; Token.Comma; Token.Eof;
    ]
    "+ - * / % = ( ) ,";
  check_kinds lex "no whitespace needed between tokens"
    [ Token.Int 1; Token.Plus; Token.Int 2; Token.Star; Token.Int 3; Token.Eof ] "1+2*3";
  (* the slash is the one operator that must be disambiguated from a comment opener *)
  check_kinds lex "division is not a comment"
    [ Token.Ident "x"; Token.Slash; Token.Ident "y"; Token.Eof ] "x/y";
  check_kinds lex "punctuation run"
    [ Token.LParen; Token.Int 1; Token.Comma; Token.Int 2; Token.RParen; Token.Eof ] "(1,2)"

let test_trivia lex () =
  check_kinds lex "newline is a token"
    [ Token.Ident "a"; Token.Newline; Token.Ident "b"; Token.Eof ] "a\nb";
  check_kinds lex "line comment leaves the newline" [ Token.Newline; Token.Int 1; Token.Eof ] "// c\n1";
  check_kinds lex "block comment is skipped"
    [ Token.Int 1; Token.Plus; Token.Int 2; Token.Eof ] "1 /* x */ + 2";
  check_kinds lex "block comments NEST" [ Token.Int 1; Token.Eof ] "/* a /* b */ c */1";
  check_kinds lex "spaces and tabs are trivia" [ Token.Int 1; Token.Int 2; Token.Eof ] "\t 1\t  2 ";
  check_kinds lex "no trailing newline => just eof" [ Token.Int 5; Token.Eof ] "5"

(* --- comments: the messiest corner of the scanner ---------------------------------
   Ground truth for every case here is `swiftc` (the behavioral oracle). The one that
   surprises C programmers: Swift block comments NEST, so `/*/*/` is two openers and one
   closer — *unterminated* — where C reads it as one finished comment. Checked:
   `swiftc -typecheck` rejects `/*/*/` with "unterminated '/*' comment". *)
let test_comments_valid lex () =
  check_kinds lex "empty block comment" [ Token.Int 1; Token.Eof ] "/**/1";
  check_kinds lex "slash immediately after the opener" [ Token.Int 1; Token.Eof ] "/*/ */ 1";
  check_kinds lex "extra stars before the closer" [ Token.Int 1; Token.Eof ] "/* a **/ 1";
  check_kinds lex "nested empty comment: open open close close" [ Token.Int 1; Token.Eof ] "/*/**/*/ 1";
  check_kinds lex "three levels of nesting" [ Token.Int 1; Token.Eof ] "/* a /* b /* c */ d */ e */ 1";
  check_kinds lex "// inside a block comment is not special" [ Token.Int 1; Token.Eof ] "/* // x */ 1";
  check_kinds lex "/* inside a line comment is not an opener"
    [ Token.Newline; Token.Int 1; Token.Eof ] "// /* x\n1";
  check_kinds lex "comment between two tokens"
    [ Token.Int 1; Token.Plus; Token.Int 2; Token.Eof ] "1 /* x */ + 2";
  check_kinds lex "back-to-back comments" [ Token.Int 8; Token.Eof ] "/* a */ /* b */ /* c */ 8";
  check_kinds lex "newlines inside a block comment are content, not tokens"
    [ Token.Int 1; Token.Eof ] "/* a\n b\n */ 1";
  (* end-of-file cases: a comment may be the last thing in the file, with no newline *)
  check_kinds lex "line comment at eof, no trailing newline" [ Token.Int 1; Token.Eof ] "1 // trailing";
  check_kinds lex "line comment is the entire file" [ Token.Eof ] "//";
  check_kinds lex "block comment is the entire file" [ Token.Eof ] "/* x */";
  check_kinds lex "empty file" [ Token.Eof ] ""

(* An unterminated block comment is an error, not a silent stop: `swiftc` reports
   "unterminated '/*' comment" and keeps going. So must we — the lexer pushes into its
   sink and still returns a token list ending in Eof. Both halves are asserted: a
   diagnostic that never surfaces and a lexer that dies are equally wrong. *)
let errors_of (ds : Diagnostics.t list) =
  List.filter (fun (d : Diagnostics.t) -> d.Diagnostics.severity = Diagnostics.Error) ds

let note_messages (ds : Diagnostics.t list) =
  List.filter_map
    (fun (d : Diagnostics.t) ->
      if d.Diagnostics.severity = Diagnostics.Note then Some d.Diagnostics.message else None)
    ds

let expect_lex_error lex name src =
  match lex src with
  | exception Failure m when String.length m >= 4 && String.sub m 0 4 = "TODO" ->
      Alcotest.failf "%s: not implemented (%s)" name m
  | exception Failure m -> Alcotest.failf "%s: raised %S instead of reporting a diagnostic" name m
  | tokens, ds ->
      if errors_of ds = [] then
        Alcotest.failf "%s: expected a diagnostic on %S, but lexed [%s] cleanly" name src
          (String.concat "; "
             (List.map (fun (t : Token.t) -> Token.string_of_kind t.Token.kind) tokens));
      (* recovery: lexing must still have finished *)
      match List.rev tokens with
      | { Token.kind = Token.Eof; _ } :: _ -> ()
      | _ -> Alcotest.failf "%s: lexing did not recover — the stream does not end in Eof" name

(* The exact diagnostics, not just "something was reported": swiftc's wording, at swiftc's
   position (end of input for an unterminated comment; the offending byte for a bad one). *)
let test_diagnostic_shape lex () =
  let _, ds = lex "let a = 1\n/* x" in
  (match errors_of ds with
  | [ d ] ->
      Alcotest.(check string) "wording" "unterminated '/*' comment" d.Diagnostics.message;
      Alcotest.(check int) "reported at end of input, line" 2 d.Diagnostics.span.Token.lo.Token.line;
      Alcotest.(check int) "…column" 5 d.Diagnostics.span.Token.lo.Token.col
  | ds -> Alcotest.failf "expected exactly one error, got %d" (List.length ds));
  (* recovery means several bad bytes in one file produce several diagnostics *)
  let tokens, ds = lex "a ` b ` c" in
  Alcotest.(check int) "one diagnostic per bad byte" 2 (List.length (errors_of ds));
  Alcotest.(check (list kind_t))
    "and the good tokens still come out"
    [ Token.Ident "a"; Token.Ident "b"; Token.Ident "c"; Token.Eof ]
    (List.map (fun (t : Token.t) -> t.Token.kind) tokens);
  match errors_of ds with
  | d :: _ ->
      Alcotest.(check string) "wording" "invalid character in source file" d.Diagnostics.message;
      Alcotest.(check int) "at the offending byte" 3 d.Diagnostics.span.Token.lo.Token.col
  | [] -> Alcotest.fail "no diagnostic"

let test_comments_unterminated lex () =
  expect_lex_error lex "bare opener" "/*";
  expect_lex_error lex "opener then a stray slash" "/*/";
  expect_lex_error lex "two openers, one closer (nesting)" "/*/*/";
  expect_lex_error lex "inner comment closed, outer left open" "/* /* */";
  expect_lex_error lex "unterminated after real tokens" "1 + /* x";
  expect_lex_error lex "unterminated spanning lines" "1\n/* x\n";
  (* and a character outside the alphabet is an error too *)
  expect_lex_error lex "stray character" "let x = `1"

let test_call_shape lex () =
  check_kinds lex "print(1 + 2)"
    [
      Token.Ident "print"; Token.LParen; Token.Int 1; Token.Plus; Token.Int 2; Token.RParen;
      Token.Newline; Token.Eof;
    ]
    "print(1 + 2)\n"

(* --- spans: positions are 1-based line/col, 0-based offset; hi is the exclusive end --- *)
let nth lex src n = List.nth (toks lex src) n

let test_spans lex () =
  let i = nth lex "  12" 0 in
  Alcotest.(check int) "int col after two spaces" 3 i.Token.span.Token.lo.Token.col;
  Alcotest.(check int) "int offset" 2 i.Token.span.Token.lo.Token.offset;
  Alcotest.(check int) "int span end col is exclusive" 5 i.Token.span.Token.hi.Token.col;
  (* a token on the second line: line/col reset after the newline *)
  let y = nth lex "x\n  y" 2 in
  Alcotest.(check int) "y on line 2" 2 y.Token.span.Token.lo.Token.line;
  Alcotest.(check int) "y at col 3" 3 y.Token.span.Token.lo.Token.col;
  (* the span covers the whole multi-digit lexeme *)
  let big = nth lex "1000" 0 in
  Alcotest.(check int) "1000 starts col 1" 1 big.Token.span.Token.lo.Token.col;
  Alcotest.(check int) "1000 ends col 5" 5 big.Token.span.Token.hi.Token.col

(* A token's span must start at the TOKEN, never at the trivia in front of it — the
   thing a kinds-only test can never catch, and what every later diagnostic points at. *)
let test_spans_after_trivia lex () =
  let nl = nth lex "// c\n1" 0 in
  Alcotest.(check int) "newline after a line comment starts at the newline" 5
    nl.Token.span.Token.lo.Token.col;
  Alcotest.(check int) "...and at its offset" 4 nl.Token.span.Token.lo.Token.offset;
  let i = nth lex "/* x */ 1" 0 in
  Alcotest.(check int) "int after a block comment" 9 i.Token.span.Token.lo.Token.col;
  let e = nth lex "// only" 0 in
  Alcotest.(check int) "eof after a line comment sits at end of input" 8
    e.Token.span.Token.lo.Token.col;
  (* newlines inside a block comment still advance the line counter *)
  let j = nth lex "/* a\n b */ 2" 0 in
  Alcotest.(check int) "token after a multi-line comment is on line 2" 2
    j.Token.span.Token.lo.Token.line

let test_eof_span lex () =
  let e = List.nth (toks lex "12") 1 in
  Alcotest.(check int) "eof offset is the input length" 2 e.Token.span.Token.lo.Token.offset;
  Alcotest.(check int) "eof span is empty" e.Token.span.Token.lo.Token.col
    e.Token.span.Token.hi.Token.col

(* Files with CRLF line endings must lex the same as LF ones: '\r' is trivia. *)
let test_crlf lex () =
  check_kinds lex "CRLF" [ Token.Int 1; Token.Newline; Token.Int 2; Token.Eof ] "1\r\n2";
  check_kinds lex "lone CR between tokens" [ Token.Int 1; Token.Int 2; Token.Eof ] "1 \r 2"

(* --- the two rungs must agree, token for token, spans included ------------------- *)

let corpus =
  [
    ""; "1"; "123"; "1 2"; "print"; "_x9"; "let var"; "lets varx let1 _let"; "+ - * / % = ( ) ,";
    "1+2*3"; "x/y"; "(1,2)"; "a\nb"; "// c\n1"; "1 /* x */ + 2"; "/* a /* b */ c */1"; "\t 1\t  2 ";
    "5"; "/**/1"; "/*/ */ 1"; "/* a **/ 1"; "/*/**/*/ 1"; "/* a /* b /* c */ d */ e */ 1";
    "/* // x */ 1"; "// /* x\n1"; "/* a */ /* b */ /* c */ 8"; "/* a\n b\n */ 1"; "1 // trailing";
    "//"; "/* x */"; "print(1 + 2)\n"; "  12"; "x\n  y"; "1000"; "// only"; "/* a\n b */ 2"; "12";
    "1\r\n2"; "1 \r 2"; "let value_9 = 1000 + 9 * 3 - 40 / 5 % 6   // row\n";
  ]

let errors = [ "/*"; "/*/"; "/*/*/"; "/* /* */"; "1 + /* x"; "1\n/* x\n"; "let x = `1" ]

(* --- the fast rung, piece by piece -----------------------------------------------
   `lexer_v1_fast.ml` has two independent holes, and they can be built (and debugged) in
   either order: the scanner only calls `pos_of` on its error path, and `pos_of` only needs
   the line table. So each gets its own test that skips until you start it — two small
   green lights instead of one big red one, and a failure points at one function.

   The full `v1_fast` suite below needs BOTH (it goes through `to_tokens`, which resolves
   every token's span), so it stays skipped until each piece stands on its own. *)

let started f = match f () with _ -> true | exception Failure m -> not (is_todo m) | exception _ -> true
let fresh () = Diagnostics.create ()
let pos_of_started () = started (fun () -> Lexer_v1_fast.pos_of [| 0 |] 0)
let lex_started () = started (fun () -> Lexer_v1_fast.lex "1" (fresh ()))

(* piece 1 — offset -> line:col. If this HANGS rather than fails, your binary search is
   not making progress: check what happens when lo = hi. *)
let test_pos_of () =
  let at src off =
    let p = Lexer_v1_fast.pos_of (Lexer_v1_fast.line_starts src) off in
    (p.Token.line, p.Token.col)
  in
  let pair = Alcotest.(pair int int) in
  let src = "ab\ncd\nef" in
  Alcotest.check pair "start of file" (1, 1) (at src 0);
  Alcotest.check pair "last byte of line 1" (1, 3) (at src 2);
  Alcotest.check pair "first byte after the newline" (2, 1) (at src 3);
  Alcotest.check pair "third line" (3, 1) (at src 6);
  Alcotest.check pair "one past the last byte (eof)" (3, 3) (at src 8);
  (* empty lines have a line-start of their own *)
  let e = "a\n\n\nb" in
  Alcotest.check pair "the empty line 2" (2, 1) (at e 2);
  Alcotest.check pair "the empty line 3" (3, 1) (at e 3);
  Alcotest.check pair "back to content on line 4" (4, 1) (at e 4);
  Alcotest.check pair "single line, no newline at all" (1, 4) (at "abc" 3);
  (* cross-check against v0 over the whole corpus: v0 maintained line/col as it scanned,
     pos_of reconstructs them from the offset alone — they must agree on every token *)
  List.iter
    (fun src ->
      List.iter
        (fun (t : Token.t) ->
          let lo = t.Token.span.Token.lo in
          Alcotest.check pair
            (Printf.sprintf "%S offset %d" src lo.Token.offset)
            (lo.Token.line, lo.Token.col)
            (at src lo.Token.offset))
        (toks v0 src))
    corpus

(* piece 2 — the scan itself, read straight out of the soup, before to_tokens exists *)
let test_soup () =
  let open Lexer_v1_fast in
  let s = lex "let x = 12" (fresh ()) in
  Alcotest.(check int) "let x = 12 is 4 tokens + eof" 5 s.n;
  Alcotest.(check int) "first token starts at 0" 0 s.starts.(0);
  Alcotest.(check int) "…and ends at 3 (exclusive)" 3 s.ends.(0);
  Alcotest.(check int) "the int literal starts at 8" 8 s.starts.(3);
  Alcotest.(check int) "…and covers both digits" 10 s.ends.(3);
  Alcotest.(check int) "eof is zero-width at end of input" 10 s.starts.(s.n - 1);
  Alcotest.(check int) "eof width" 0 (s.ends.(s.n - 1) - s.starts.(s.n - 1));
  (* trivia produces no tokens; a newline does *)
  Alcotest.(check int) "comment is skipped" 2 (lex "/* x */ 1" (fresh ())).n;
  Alcotest.(check int) "newline is a token" 4 (lex "a\nb" (fresh ())).n;
  (* offsets are enough to recover the text — that is the point of the columnar soup *)
  let s = lex "print(42)" (fresh ()) in
  Alcotest.(check string) "lexeme by offsets" "print"
    (String.sub s.src s.starts.(0) (s.ends.(0) - s.starts.(0)))


let diag_t =
  Alcotest.testable
    (fun ppf (d : Diagnostics.t) ->
      Format.pp_print_string ppf (Diagnostics.to_string d))
    ( = )

let test_rungs_agree () =
  List.iter
    (fun src ->
      Alcotest.check (Alcotest.list token_t)
        (Printf.sprintf "v1_fast == v0 on %S" src)
        (toks v0 src) (toks v1 src))
    corpus;
  (* they must also agree about what is NOT lexable — same wording, same positions *)
  List.iter
    (fun src ->
      expect_lex_error v0 "v0 reports" src;
      expect_lex_error v1 "v1_fast reports" src;
      (* ERRORS must match exactly — same wording, same position, same count. *)
      Alcotest.check (Alcotest.list diag_t)
        (Printf.sprintf "same errors on %S" src)
        (errors_of (snd (v0 src)))
        (errors_of (snd (v1 src)));
      (* NOTES: the fast rung's scanner is given, so it always emits the pair from §6
         exercise 2; v0 only does once you have done the exercise. Compare them when v0 has
         them, and compare only the WORDING — where you hang a note is your call (§6). *)
      let n0 = note_messages (snd (v0 src)) in
      if n0 <> [] then
        Alcotest.(check (list string))
          (Printf.sprintf "same notes on %S" src)
          n0
          (note_messages (snd (v1 src))))
    errors

let suite (rung : string) (lex : rung) =
  let case name f = Alcotest.test_case name `Quick (f lex) in
  [
    (rung ^ " literals/idents", [ case "ints and identifiers" test_literals_idents ]);
    (rung ^ " keywords", [ case "keyword table + munch" test_keywords ]);
    (rung ^ " operators", [ case "operators and punctuation" test_operators ]);
    (rung ^ " trivia", [ case "whitespace and comments" test_trivia ]);
    ( rung ^ " comments",
      [
        case "every valid comment shape" test_comments_valid;
        case "unterminated is an error" test_comments_unterminated;
        case "wording, span, recovery" test_diagnostic_shape;
      ] );
    (rung ^ " line endings", [ case "CRLF" test_crlf ]);
    (rung ^ " calls", [ case "call token shape" test_call_shape ]);
    ( rung ^ " spans",
      [
        case "source positions" test_spans;
        case "spans start after trivia" test_spans_after_trivia;
        case "eof span" test_eof_span;
      ] );
  ]

(* Has the fast rung been started? A `TODO(...)` failure means "still a skeleton" (skip);
   any other outcome — including a wrong answer or a different exception — means it is
   being worked on, so run everything and report properly. *)
let v1_started = lex_started () && pos_of_started ()

let skip what () = Printf.printf "    (%s not started — this check activates as soon as it is)\n%!" what

let piece name started what test =
  ( name,
    [
      (if started () then Alcotest.test_case "checked" `Quick test
       else Alcotest.test_case ("skipped — " ^ what ^ " not written yet") `Quick (skip what));
    ] )

let () =
  Alcotest.run "lexer"
    (suite "v0" v0
    @ [
        piece "v1_fast piece: pos_of" pos_of_started "TODO(01-v1b) pos_of" test_pos_of;
        piece "v1_fast piece: lex" lex_started "TODO(01-v1a) lex" test_soup;
      ]
    @
    if v1_started then
      suite "v1_fast" v1
      @ [
          ( "equivalence",
            [ Alcotest.test_case "v1 == v0, kinds and spans" `Quick test_rungs_agree ] );
        ]
    else
      [
        ( "v1_fast",
          [
            Alcotest.test_case "skipped — lexer_v1_fast.ml is still a skeleton" `Quick (fun () ->
                ());
          ] );
      ])
