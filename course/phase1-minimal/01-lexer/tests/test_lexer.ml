(* Alcotest unit tests for the lexer (concept 01).

   These call [Lexer.tokenize] in-process and assert the exact [Token.kind] list AND
   source spans (line/col/offset) — finer-grained than the cram `--emit-tokens` golden
   test, which only sees the printed kinds and never checks positions.

   RED until you implement `lexer.ml : next`; GREEN against `solution/lexer.ml`.
   Run:  dune build @phase1-minimal/01-lexer/runtest *)

let lex (src : string) : Token.t list = Lexer.tokenize (Lexer.create src)
let kinds (src : string) : Token.kind list = List.map (fun (t : Token.t) -> t.Token.kind) (lex src)

let kind_t =
  Alcotest.testable (fun ppf k -> Format.pp_print_string ppf (Token.string_of_kind k)) ( = )

let check_kinds name expected src = Alcotest.check (Alcotest.list kind_t) name expected (kinds src)

let test_literals_idents () =
  check_kinds "empty input" [ Token.Eof ] "";
  check_kinds "single int" [ Token.Int 1; Token.Eof ] "1";
  check_kinds "maximal-munch int" [ Token.Int 123; Token.Eof ] "123";
  check_kinds "two ints separated" [ Token.Int 1; Token.Int 2; Token.Eof ] "1 2";
  check_kinds "identifier" [ Token.Ident "print"; Token.Eof ] "print";
  check_kinds "ident leading _ and digits" [ Token.Ident "_x9"; Token.Eof ] "_x9"

let test_keywords () =
  check_kinds "let/var are keywords" [ Token.Kw_let; Token.Kw_var; Token.Eof ] "let var";
  (* keyword match is whole-word only — these are identifiers, not keyword + suffix *)
  check_kinds "keyword maximal munch"
    [ Token.Ident "lets"; Token.Ident "varx"; Token.Ident "let1"; Token.Ident "_let"; Token.Eof ]
    "lets varx let1 _let"

let test_operators () =
  check_kinds "all operators and punctuation"
    [
      Token.Plus; Token.Minus; Token.Star; Token.Slash; Token.Percent; Token.Eq; Token.LParen;
      Token.RParen; Token.Comma; Token.Eof;
    ]
    "+ - * / % = ( ) ,"

let test_trivia () =
  check_kinds "newline is a token" [ Token.Ident "a"; Token.Newline; Token.Ident "b"; Token.Eof ] "a\nb";
  check_kinds "line comment leaves the newline" [ Token.Newline; Token.Int 1; Token.Eof ] "// c\n1";
  check_kinds "block comment is skipped" [ Token.Int 1; Token.Plus; Token.Int 2; Token.Eof ] "1 /* x */ + 2";
  check_kinds "block comments NEST" [ Token.Int 1; Token.Eof ] "/* a /* b */ c */1";
  check_kinds "spaces and tabs are trivia" [ Token.Int 1; Token.Int 2; Token.Eof ] "\t 1\t  2 ";
  check_kinds "no trailing newline => just eof" [ Token.Int 5; Token.Eof ] "5"

let test_call_shape () =
  check_kinds "print(1 + 2)"
    [
      Token.Ident "print"; Token.LParen; Token.Int 1; Token.Plus; Token.Int 2; Token.RParen;
      Token.Newline; Token.Eof;
    ]
    "print(1 + 2)\n"

(* --- spans: positions are 1-based line/col, 0-based offset; hi is the exclusive end --- *)
let nth src n = List.nth (lex src) n

let test_spans () =
  let i = nth "  12" 0 in
  Alcotest.(check int) "int col after two spaces" 3 i.Token.span.Token.lo.Token.col;
  Alcotest.(check int) "int offset" 2 i.Token.span.Token.lo.Token.offset;
  Alcotest.(check int) "int span end col is exclusive" 5 i.Token.span.Token.hi.Token.col;
  (* a token on the second line: line/col reset after the newline *)
  let y = nth "x\n  y" 2 in
  Alcotest.(check int) "y on line 2" 2 y.Token.span.Token.lo.Token.line;
  Alcotest.(check int) "y at col 3" 3 y.Token.span.Token.lo.Token.col;
  (* the span covers the whole multi-digit lexeme *)
  let big = nth "1000" 0 in
  Alcotest.(check int) "1000 starts col 1" 1 big.Token.span.Token.lo.Token.col;
  Alcotest.(check int) "1000 ends col 5" 5 big.Token.span.Token.hi.Token.col

let () =
  Alcotest.run "lexer"
    [
      ("literals/idents", [ Alcotest.test_case "ints and identifiers" `Quick test_literals_idents ]);
      ("keywords", [ Alcotest.test_case "keyword table + munch" `Quick test_keywords ]);
      ("operators", [ Alcotest.test_case "operators and punctuation" `Quick test_operators ]);
      ("trivia", [ Alcotest.test_case "whitespace, comments, newlines" `Quick test_trivia ]);
      ("calls", [ Alcotest.test_case "call token shape" `Quick test_call_shape ]);
      ("spans", [ Alcotest.test_case "source positions" `Quick test_spans ]);
    ]
