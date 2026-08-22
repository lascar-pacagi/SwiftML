(* Tests for the §6 EXERCISES.

   These run as part of `make lab`, but each group first probes whether you have STARTED
   that exercise: an untouched lexer reports the group as skipped (green), and the moment
   your lexer behaves differently from the stock one the real assertions switch on. Same
   convention as the v1_fast rung — nothing here can make `make lab` red before you have
   chosen to work on it, and nothing here is silently forgotten once you have.

     make lab       C=phase1-minimal/01-lexer     concept + rungs + exercises
     make exercises C=phase1-minimal/01-lexer     just this file, when you want focus

   All three are self-contained in THIS directory — lexer.ml, plus one stub in token.ml for
   exercise 3. None of them asks you to edit a later concept.

   Every expectation below was checked against `swiftc` — the exercises extend the
   lexer *towards* Swift, so the oracle decides what "right" means. *)

let lex_with (src : string) : Token.t list * Diagnostics.t list =
  let d = Diagnostics.create () in
  let toks = Lexer.tokenize (Lexer.create src d) in
  (toks, Diagnostics.all d)

let lex (src : string) : Token.t list = fst (lex_with src)
let kinds (src : string) : Token.kind list = List.map (fun (t : Token.t) -> t.Token.kind) (lex src)

let kind_t =
  Alcotest.testable (fun ppf k -> Format.pp_print_string ppf (Token.string_of_kind k)) ( = )

let check_kinds name expected src = Alcotest.check (Alcotest.list kind_t) name expected (kinds src)

(* --- Exercise 1: `_` as a digit separator ---------------------------------------
   `swiftc` accepts an underscore anywhere AFTER the first digit, in any number:
   1_000_000, 1_0_0, 1__0 and even a trailing 1_ all compile (1_000_000 prints
   1000000). A LEADING underscore is not a number at all — `_1000` is an identifier,
   which is why swiftc answers "cannot find '_1000' in scope". *)
let test_digit_separators () =
  check_kinds "the classic" [ Token.Int 1000000; Token.Eof ] "1_000_000";
  check_kinds "separators anywhere after the first digit" [ Token.Int 100; Token.Eof ] "1_0_0";
  check_kinds "doubled separator" [ Token.Int 10; Token.Eof ] "1__0";
  check_kinds "trailing separator (swiftc accepts it)" [ Token.Int 1; Token.Eof ] "1_";
  check_kinds "leading underscore is an IDENTIFIER, not a number"
    [ Token.Ident "_1000"; Token.Eof ] "_1000";
  check_kinds "separators do not glue two literals together"
    [ Token.Int 1000; Token.Plus; Token.Int 2000; Token.Eof ] "1_000 + 2_000";
  (* the span still covers the written lexeme, underscores included *)
  let t = List.hd (lex "1_000") in
  Alcotest.(check int) "span covers the whole literal" 6 t.Token.span.Token.hi.Token.col

(* --- Exercise 2: point at the comment that ran away -----------------------------
   The base lexer already reports `unterminated '/*' comment` — at end of input, which is
   where the scanner ran out of file, and where swiftc puts it too. swiftc then says two
   more things, and both are worth having:

     u.swift:5:9: error: unterminated '/*' comment
     3 | /* opener here
       | `- note: comment started here
       (plus a fix-it that inserts `*/` once per open level)

   1. A NOTE at the opener — where you have to go and type `*/`. Remember the opener's
      `Token.pos` before consuming `/*` and emit a `Diagnostics.Note` there. For NESTED
      comments point at the OUTERMOST opener: swiftc's `skipSlashStarComment` scans the
      whole thing in one pass with a depth counter, so its `StartPtr` never moves.
   2. A second note carrying THE REPAIR. swiftc attaches a fix-it built as `"*/"` repeated
      *depth* times (`Terminator` in Lexer.cpp); we have no fix-it machinery, so say it in
      words, at end of input where the text would go:

        4:1: error: unterminated '/*' comment
        2:1: note: comment started here
        4:1: note: insert '*/*/' to close these 2 nested comments

      One open level reads `insert '*/' to close this comment`. That means carrying the
      depth out of the loop alongside the opener. *)
let notes_of (ds : Diagnostics.t list) =
  List.filter (fun (d : Diagnostics.t) -> d.Diagnostics.severity = Diagnostics.Note) ds

let note_saying pred ds = List.find_opt (fun (d : Diagnostics.t) -> pred d.Diagnostics.message) (notes_of ds)
let starts_with pre s = String.length s >= String.length pre && String.sub s 0 (String.length pre) = pre

let expect_note ~name ~line ~col src =
  let _, ds = lex_with src in
  match note_saying (( = ) "comment started here") ds with
  | None -> Alcotest.failf "%s: no note — the error alone does not say where the comment opened" name
  | Some n ->
      Alcotest.(check int) (name ^ ": line") line n.Diagnostics.span.Token.lo.Token.line;
      Alcotest.(check int) (name ^ ": column") col n.Diagnostics.span.Token.lo.Token.col

(* our stand-in for swiftc's fix-it: the exact text to insert, at the insertion point *)
let expect_repair ~name ~msg src =
  let _, ds = lex_with src in
  match note_saying (starts_with "insert") ds with
  | None -> Alcotest.failf "%s: no note saying what to insert" name
  | Some n -> Alcotest.(check string) (name ^ ": repair") msg n.Diagnostics.message

let test_unterminated_points_at_the_opener () =
  expect_note ~name:"opener on its own line" ~line:3 ~col:1
    "let a = 1\nlet b = 2\n/* opener here\nlet c = 3\n";
  expect_note ~name:"mid-line opener" ~line:1 ~col:9 "let x = /* oops";
  expect_note ~name:"nested: the OUTERMOST opener" ~line:1 ~col:1
    "/* outer /* inner */ still open";
  (* the repair note: one '*/' per level still open, at end of input *)
  expect_repair ~name:"one level" ~msg:"insert '*/' to close this comment" "let x = /* oops";
  expect_repair ~name:"two levels" ~msg:"insert '*/*/' to close these 2 nested comments"
    "/* outer /* inner still open";
  expect_repair ~name:"three levels"
    ~msg:"insert '*/*/*/' to close these 3 nested comments" "/* a /* b /* c";
  (* the error itself must survive alongside the note, and lexing must still recover *)
  let tokens, ds = lex_with "let x = /* oops" in
  Alcotest.(check int) "still exactly one error" 1
    (List.length
       (List.filter (fun (d : Diagnostics.t) -> d.Diagnostics.severity = Diagnostics.Error) ds));
  match List.rev tokens with
  | { Token.kind = Token.Eof; _ } :: _ -> ()
  | _ -> Alcotest.fail "lexing must still recover and end in Eof"

(* --- Exercise 3: show the spans (`Token.string_of_token`) ------------------------
   Every printer in the concept throws spans away — `string_of_kind` gives you `int(20)`
   and the position it was found at is lost. Implement `Token.string_of_token` (it ships as
   a stub in token.ml) so a token renders as `<kind> @ <line>:<col>-<line>:<col>`, and the
   positions the lexer has been carefully maintaining finally become visible.

   Self-contained: the function lives in this directory, next to the kind printer. Wiring it
   into `swiftml --emit-tokens` afterwards is one line in concept 04's driver — worth doing,
   but outside this concept, so nothing here depends on it. *)
let expected_dump =
  [
    "let @ 1:1-1:4"; "ident(x) @ 1:5-1:6"; "= @ 1:7-1:8"; "int(1) @ 1:9-1:10";
    "newline @ 1:10-2:1"; "ident(print) @ 2:1-2:6"; "( @ 2:6-2:7"; "ident(x) @ 2:7-2:8";
    "+ @ 2:9-2:10"; "int(20) @ 2:11-2:13"; ") @ 2:13-2:14"; "newline @ 2:14-3:1"; "eof @ 3:1-3:1";
  ]

let test_string_of_token () =
  Alcotest.(check (list string))
    "kind @ line:col-line:col" expected_dump
    (List.map Token.string_of_token (lex "let x = 1\nprint(x + 20)\n"));
  (* a span can cross a line break: the newline token ends at column 1 of the next line *)
  Alcotest.(check string) "newline span crosses the line break" "newline @ 1:2-2:1"
    (Token.string_of_token (List.nth (lex "a\nb") 1))

(* --- "have you started this one?" probes -----------------------------------------
   Each probe compares against what the STOCK lexer does. Anything else — including a
   half-finished or wrong attempt — counts as started, so a bug shows up as a red test
   rather than a silent skip. *)

(* Exercise 1 is untouched while `1_000_000` still lexes as `1` followed by an identifier. *)
let is_todo (m : string) = String.length m >= 4 && String.sub m 0 4 = "TODO"

let ex1_started () =
  match kinds "1_000_000" with
  | [ Token.Int 1; Token.Ident "_000_000"; Token.Eof ] -> false
  (* a lexer that is still the TODO skeleton has not started ANY exercise *)
  | exception Failure m when is_todo m -> false
  | _ -> true
  | exception _ -> true

(* Exercise 2 is untouched while the sink holds no Note for an unterminated comment. *)
let ex2_started () =
  match lex_with "let x = /* oops" with
  | _, ds -> notes_of ds <> []
  (* a lexer that still RAISES has not adopted the sink yet — that is the base contract's
     problem (the v0 suite reports it), not this exercise's *)
  | exception _ -> false

(* Exercise 3 is untouched while `Token.string_of_token` is still the TODO stub. *)
let ex3_started () =
  match Token.string_of_token (List.hd (lex "1")) with
  | _ -> true
  | exception Failure m -> not (is_todo m)
  | exception _ -> false

let skipped what () =
  Printf.printf "    (%s not started — this group activates as soon as it is)\n%!" what

let group name started what test =
  ( name,
    [
      (if started () then Alcotest.test_case "checked" `Quick test
       else Alcotest.test_case ("skipped — " ^ what ^ " not started") `Quick (skipped what));
    ] )

let () =
  Alcotest.run "lexer exercises"
    [
      group "ex1 digit separators" ex1_started "1_000_000" test_digit_separators;
      group "ex2 unterminated comment" ex2_started "the opener position"
        test_unterminated_points_at_the_opener;
      group "ex3 token spans" ex3_started "Token.string_of_token" test_string_of_token;
    ]
