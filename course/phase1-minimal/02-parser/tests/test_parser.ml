(* Alcotest unit tests for the parser (concept 02).

   These parse in-process and assert (a) AST *structure* via the span-free S-expr dump,
   (b) statement-kind discrimination by pattern-matching the real nodes, (c) multi-argument
   call parsing, and (d) that malformed input produces diagnostics — recovery the cram
   `--emit-ast` golden test does not exercise.

   The groups follow the THREE HOLES, and each one drives its own entry point, so you can
   fill them in order and watch the suite go green a layer at a time:

     expr      TODO(02a)  ->  Parser.parse_expr   (needs neither of the others)
     stmt      TODO(02b)  ->  Parser.parse_stmt   (uses your expression parser)
     program   TODO(02c)  ->  Parser.parse_program

   All of them are RED on the shipped skeleton — that is the point — but a failure now names
   the layer that is missing instead of failing everywhere at once.

   GREEN against `solution/parser.ml`. *)

(* a parser over `src`'s tokens, for driving one production directly *)
let mk_d (src : string) : Parser.t * Diagnostics.sink =
  let diags = Diagnostics.create () in
  (Parser.create (Lexer.tokenize (Lexer.create src diags)) diags, diags)

let mk (src : string) : Parser.t = fst (mk_d src)

(* --- layer 1: expressions (TODO(02a)) — parse_expr only ------------------------- *)
let dump_of_expr (src : string) : string = Ast.dump_expr (Parser.parse_expr (mk src))
let check_expr name expected src = Alcotest.(check string) name expected (dump_of_expr src)

let test_expr_precedence () =
  check_expr "* binds tighter than +" "(+ 1 (* 2 3))" "1 + 2 * 3";
  check_expr "parentheses override" "(* (+ 1 2) 3)" "(1 + 2) * 3";
  check_expr "- is left associative" "(- (- 10 4) 3)" "10 - 4 - 3";
  check_expr "/ and % share a level, left assoc, above +" "(+ 1 (% (/ 20 4) 3))" "1 + 20 / 4 % 3";
  check_expr "nested parens collapse" "7" "((7))";
  (* every operator at once: both levels, both associativities, one derivation *)
  check_expr "all five operators in one expression" "(- (+ 1 2) (% (/ (* 3 4) 5) 6))"
    "1 + 2 - 3 * 4 / 5 % 6";
  check_expr "a long chain stays left-leaning" "(+ (+ (+ 1 2) 3) 4)" "1 + 2 + 3 + 4"

let test_expr_unary () =
  check_expr "unary minus then binary +" "(+ (- 5) 8)" "-5 + 8";
  check_expr "unary binds tighter than *" "(* 2 (- 3))" "2 * -3";
  check_expr "unary applies to a variable" "(- x)" "-x"

let test_expr_calls () =
  check_expr "a call is a primary" "(print 1)" "print(1)";
  (* the two ends of the argument list: none at all, and one that STARTS with a paren *)
  (* dump_expr joins args with a space, so a no-argument call renders with a trailing one *)
  check_expr "zero arguments" "(f )" "f()";
  check_expr "an argument may start with '('" "(print (* (+ 1 2) 3))" "print((1 + 2) * 3)";
  match Parser.parse_expr (mk "f(1, 2, 3)") with
  | Ast.Call ("f", [ a; b; c ], _) ->
      Alcotest.(check string) "arg0" "1" (Ast.dump_expr a);
      Alcotest.(check string) "arg1" "2" (Ast.dump_expr b);
      Alcotest.(check string) "arg2" "3" (Ast.dump_expr c)
  | _ -> Alcotest.fail "expected a 3-argument call (comma-separated args)"

let test_expr_nested_calls () =
  check_expr "a call may be an argument" "(print (f 1))" "print(f(1))";
  check_expr "arguments are full expressions" "(f (+ 1 2) (- 3) 4)" "f(1+2, -3, (4))"

(* diagnostics an EXPRESSION can raise on its own — no statement or program needed *)
let ndiags_expr (src : string) : int =
  let p, d = mk_d src in
  ignore (Parser.parse_expr p);
  List.length (Diagnostics.all d)

let test_expr_errors () =
  Alcotest.(check int) "valid expr: no diagnostics" 0 (ndiags_expr "1 + 2 * 3");
  Alcotest.(check bool) "trailing operator is reported" true (ndiags_expr "1 +" >= 1);
  Alcotest.(check bool) "missing ')' is reported" true (ndiags_expr "print(1" >= 1)

(* Spans. Nothing downstream can point at source without them: concept 03 reports
   "cannot find 'x' in scope" AT a span, and Phase 8 turns statement spans into DWARF
   lines. The dump above is span-free, so these are the only assertions that check them. *)
let lo_col (e : Ast.expr) = (Ast.expr_span e).Token.lo.Token.col
let hi_col (e : Ast.expr) = (Ast.expr_span e).Token.hi.Token.col

let test_expr_spans () =
  (match Parser.parse_expr (mk "1 + 2 * 3") with
  | Ast.Binary (_, l, r, sp) ->
      Alcotest.(check int) "a binary starts where its LEFT operand starts" (lo_col l)
        sp.Token.lo.Token.col;
      Alcotest.(check int) "...and ends where its RIGHT operand ends" (hi_col r)
        sp.Token.hi.Token.col
  | _ -> Alcotest.fail "expected a binary at the root");
  (match Parser.parse_expr (mk "-5 + 8") with
  | Ast.Binary (_, Ast.Unary (_, _, us), _, _) ->
      Alcotest.(check int) "unary minus starts at the '-'" 1 us.Token.lo.Token.col
  | _ -> Alcotest.fail "expected (+ (- 5) 8)");
  match Parser.parse_expr (mk "print(1 + 2)") with
  | Ast.Call (_, _, sp) ->
      Alcotest.(check int) "a call starts at the callee" 1 sp.Token.lo.Token.col;
      Alcotest.(check int) "...and covers the closing paren" 13 sp.Token.hi.Token.col
  | _ -> Alcotest.fail "expected a call"

(* --- layer 2: statements (TODO(02b)) — parse_stmt only -------------------------- *)
let test_stmt_kinds () =
  (match Parser.parse_stmt (mk "let a = 6") with
  | Ast.Let { name = "a"; is_var = false; _ } -> ()
  | _ -> Alcotest.fail "expected a `let` binding");
  (match Parser.parse_stmt (mk "var c = 1") with
  | Ast.Let { name = "c"; is_var = true; _ } -> ()
  | _ -> Alcotest.fail "expected a `var` binding");
  (match Parser.parse_stmt (mk "c = c * 2") with
  | Ast.Assign { name = "c"; _ } -> ()
  | _ -> Alcotest.fail "expected an assignment (one token of lookahead past the ident)");
  (match Parser.parse_stmt (mk "print(1)") with
  | Ast.Expr_stmt (Ast.Call ("print", [ _ ], _), _) -> ()
  | _ -> Alcotest.fail "expected a print call expression statement");
  (* a bare expression is a statement too — not only calls *)
  match Parser.parse_stmt (mk "1 + 2") with
  | Ast.Expr_stmt (e, _) -> Alcotest.(check string) "bare expression statement" "(+ 1 2)" (Ast.dump_expr e)
  | _ -> Alcotest.fail "expected an expression statement"

(* A malformed binding is reported by parse_stmt, not by the expression parser. *)
let ndiags_stmt (src : string) : int =
  let p, d = mk_d src in
  ignore (Parser.parse_stmt p);
  List.length (Diagnostics.all d)

let test_stmt_errors () =
  Alcotest.(check int) "a good binding is clean" 0 (ndiags_stmt "let a = 1");
  Alcotest.(check bool) "missing name is reported" true (ndiags_stmt "let = 1" >= 1);
  Alcotest.(check bool) "missing '=' is reported" true (ndiags_stmt "let a 1" >= 1)

(* --- layer 3: whole programs (TODO(02c)) ---------------------------------------- *)
let parse (src : string) : Ast.program * Diagnostics.sink =
  let diags = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src diags)) diags) in
  (p, diags)

let prog src = fst (parse src)
let ndiags src = List.length (Diagnostics.all (snd (parse src)))

let test_program_multi () =
  let stmts = (prog "let a = 6\nvar c = a + 7\nc = c * 2\n").Ast.stmts in
  Alcotest.(check int) "three statements" 3 (List.length stmts);
  match stmts with
  | [ Ast.Let { is_var = false; _ }; Ast.Let { is_var = true; _ }; Ast.Assign _ ] -> ()
  | _ -> Alcotest.fail "expected let; var; assign"

let dumps src = List.map Ast.dump_stmt (prog src).Ast.stmts

let test_program_blank_lines () =
  Alcotest.(check int) "blank and comment-only lines are not statements" 2
    (List.length (prog "\n// just a comment\n\nlet a = 1\n\nprint(a)\n").Ast.stmts);
  Alcotest.(check int) "a last line without a newline still counts" 1
    (List.length (prog "print(1)").Ast.stmts);
  (* ...and is not an error: Eof terminates the last statement just as a newline would.
     A file need not end with a blank line, and every test that builds a source string
     in OCaml (concept 03's, for one) ends without one. *)
  Alcotest.(check int) "a last line without a newline is CLEAN" 0 (ndiags "print(1)");
  Alcotest.(check int) "...also after several statements" 0
    (ndiags "let a = 1\nvar b = 2\nprint(a + b)");
  (* runs of newlines before, between and after the statements *)
  Alcotest.(check (list string)) "multiple blank lines everywhere"
    [ "(let a 1)"; "(print a)" ]
    (dumps "\n\n\nlet a = 1\n\n\n\nprint(a)\n\n");
  Alcotest.(check int) "an empty file is an empty program" 0 (List.length (prog "").Ast.stmts);
  Alcotest.(check int) "...and reports nothing" 0 (ndiags "")

(* Things the grammar does NOT accept. Each must be REPORTED — the parser is allowed to
   recover however it likes, so these assert that a diagnostic exists, not how many. *)
let rejects name src =
  Alcotest.(check bool) (Printf.sprintf "%s: %S is rejected" name src) true (ndiags src >= 1)

let test_program_rejects () =
  rejects "missing initializer" "let a =\n";
  rejects "name must be an identifier" "let 5 = 3\n";
  rejects "missing '='" "let a 1\n";
  rejects "keyword as a name" "let let = 1\n";
  rejects "double '='" "a = = 3\n";
  (* NOT here: `f(1,)`. Swift 6.1 accepted trailing commas (SE-0439) and swiftc 6.3
     typechecks `print(1,)` happily, so a parser that rejects it is stricter than the
     oracle — see §2. Our grammar has no rule for it either way, so neither behaviour is
     asserted. *)
  rejects "unclosed parenthesis" "(1 + 2\n";
  rejects "a call needs its parentheses" "print 1\n";
  rejects "a stray closing parenthesis" ")\n";
  rejects "two operators in a row" "1 +* 2\n";
  (* the control: none of the shapes above is rejected by accident *)
  Alcotest.(check int) "a valid program is still clean" 0
    (ndiags "let a = 1\nvar b = a * 2\nb = b - 1\nprint(b)\n")

(* Recovery: one run reports the broken line AND still returns the good statements.
   The base parser manages this because the prefix error consumes a token (§3); §9's
   exercise 1 makes it deliberate with skip-to-newline panic mode. *)
let test_program_recovery () =
  let p, d = mk_d "let a = 1\nlet b = *\nprint(a)\n" in
  let prog = Parser.parse_program p in
  Alcotest.(check bool) "the bad line is reported" true (List.length (Diagnostics.all d) >= 1);
  Alcotest.(check bool) "parsing continued to the end" true
    (List.length prog.Ast.stmts >= 2)

let test_program_errors () =
  Alcotest.(check int) "a valid program is clean" 0 (ndiags "let a = 1\nprint(a)\n");
  (* two statements on one line: the program layer is what notices *)
  Alcotest.(check bool) "missing statement separator is reported" true (ndiags "1 2\n" >= 1)

let () =
  Alcotest.run "parser"
    [
      (* layer 1 — TODO(02a), needs only parse_expr *)
      ("expr: precedence", [ Alcotest.test_case "precedence & associativity" `Quick test_expr_precedence ]);
      ("expr: unary", [ Alcotest.test_case "unary minus" `Quick test_expr_unary ]);
      ("expr: calls", [ Alcotest.test_case "comma-separated args" `Quick test_expr_calls ]);
      ("expr: nesting", [ Alcotest.test_case "calls and parens nest" `Quick test_expr_nested_calls ]);
      ("expr: errors", [ Alcotest.test_case "diagnostics from an expression" `Quick test_expr_errors ]);
      ("expr: spans", [ Alcotest.test_case "spans cover their operands" `Quick test_expr_spans ]);
      (* layer 2 — TODO(02b), needs parse_stmt (and your expression parser) *)
      ("stmt: kinds", [ Alcotest.test_case "statement kinds" `Quick test_stmt_kinds ]);
      ("stmt: errors", [ Alcotest.test_case "malformed bindings" `Quick test_stmt_errors ]);
      (* layer 3 — TODO(02c), the only group that genuinely needs parse_program *)
      ("program: many statements", [ Alcotest.test_case "several statements" `Quick test_program_multi ]);
      ("program: blank lines", [ Alcotest.test_case "newlines and eof" `Quick test_program_blank_lines ]);
      ("program: errors", [ Alcotest.test_case "statement separators" `Quick test_program_errors ]);
      ("program: recovery", [ Alcotest.test_case "reports and keeps going" `Quick test_program_recovery ]);
      ("program: rejects", [ Alcotest.test_case "malformed programs are reported" `Quick test_program_rejects ]);
    ]
