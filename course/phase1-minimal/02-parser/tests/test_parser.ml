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
  check_expr "nested parens collapse" "7" "((7))"

let test_expr_unary () =
  check_expr "unary minus then binary +" "(+ (- 5) 8)" "-5 + 8";
  check_expr "unary binds tighter than *" "(* 2 (- 3))" "2 * -3";
  check_expr "unary applies to a variable" "(- x)" "-x"

let test_expr_calls () =
  check_expr "a call is a primary" "(print 1)" "print(1)";
  match Parser.parse_expr (mk "f(1, 2, 3)") with
  | Ast.Call ("f", [ a; b; c ], _) ->
      Alcotest.(check string) "arg0" "1" (Ast.dump_expr a);
      Alcotest.(check string) "arg1" "2" (Ast.dump_expr b);
      Alcotest.(check string) "arg2" "3" (Ast.dump_expr c)
  | _ -> Alcotest.fail "expected a 3-argument call (comma-separated args)"

(* diagnostics an EXPRESSION can raise on its own — no statement or program needed *)
let ndiags_expr (src : string) : int =
  let p, d = mk_d src in
  ignore (Parser.parse_expr p);
  List.length (Diagnostics.all d)

let test_expr_errors () =
  Alcotest.(check int) "valid expr: no diagnostics" 0 (ndiags_expr "1 + 2 * 3");
  Alcotest.(check bool) "trailing operator is reported" true (ndiags_expr "1 +" >= 1);
  Alcotest.(check bool) "missing ')' is reported" true (ndiags_expr "print(1" >= 1)

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
  match Parser.parse_stmt (mk "print(1)") with
  | Ast.Expr_stmt (Ast.Call ("print", [ _ ], _), _) -> ()
  | _ -> Alcotest.fail "expected a print call expression statement"

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

let test_program_blank_lines () =
  Alcotest.(check int) "blank and comment-only lines are not statements" 2
    (List.length (prog "\n// just a comment\n\nlet a = 1\n\nprint(a)\n").Ast.stmts);
  Alcotest.(check int) "a last line without a newline still counts" 1
    (List.length (prog "print(1)").Ast.stmts)

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
      ("expr: errors", [ Alcotest.test_case "diagnostics from an expression" `Quick test_expr_errors ]);
      (* layer 2 — TODO(02b), needs parse_stmt (and your expression parser) *)
      ("stmt: kinds", [ Alcotest.test_case "statement kinds" `Quick test_stmt_kinds ]);
      (* layer 3 — TODO(02c), the only group that genuinely needs parse_program *)
      ("program: many statements", [ Alcotest.test_case "several statements" `Quick test_program_multi ]);
      ("program: blank lines", [ Alcotest.test_case "newlines and eof" `Quick test_program_blank_lines ]);
      ("program: errors", [ Alcotest.test_case "statement separators" `Quick test_program_errors ]);
    ]
