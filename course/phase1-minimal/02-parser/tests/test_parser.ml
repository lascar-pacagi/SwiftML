(* Alcotest unit tests for the parser (concept 02).

   These parse in-process and assert (a) AST *structure* via the span-free S-expr dump,
   (b) statement-kind discrimination by pattern-matching the real nodes, (c) multi-argument
   call parsing, and (d) that malformed input produces diagnostics — recovery the cram
   `--emit-ast` golden test does not exercise.

   RED until you implement `parser.ml`; GREEN against `solution/parser.ml`. *)

let parse (src : string) : Ast.program * Diagnostics.sink =
  let diags = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) diags) in
  (p, diags)

let prog src = fst (parse src)
let ndiags src = List.length (Diagnostics.all (snd (parse src)))

(* Extract the single expression of a one-line expression-statement program. *)
let expr_of src =
  match (prog src).Ast.stmts with
  | [ Ast.Expr_stmt (e, _) ] -> e
  | _ -> Alcotest.fail "expected a single expression statement"

let dump src = Ast.dump_expr (expr_of src)
let check_dump name expected src = Alcotest.(check string) name expected (dump src)

let test_precedence_assoc () =
  check_dump "* binds tighter than +" "(+ 1 (* 2 3))" "1 + 2 * 3";
  check_dump "parentheses override" "(* (+ 1 2) 3)" "(1 + 2) * 3";
  check_dump "- is left associative" "(- (- 10 4) 3)" "10 - 4 - 3";
  check_dump "/ and % share a level, left assoc, above +" "(+ 1 (% (/ 20 4) 3))" "1 + 20 / 4 % 3";
  check_dump "nested parens collapse" "7" "((7))"

let test_unary () =
  check_dump "unary minus then binary +" "(+ (- 5) 8)" "-5 + 8";
  check_dump "unary binds tighter than *" "(* 2 (- 3))" "2 * -3";
  check_dump "unary applies to a variable" "(- x)" "-x"

let test_statements () =
  (match (prog "let a = 6").Ast.stmts with
  | [ Ast.Let { name = "a"; is_var = false; _ } ] -> ()
  | _ -> Alcotest.fail "expected a `let` binding");
  (match (prog "var c = 1").Ast.stmts with
  | [ Ast.Let { name = "c"; is_var = true; _ } ] -> ()
  | _ -> Alcotest.fail "expected a `var` binding");
  (match (prog "c = c * 2").Ast.stmts with
  | [ Ast.Assign { name = "c"; _ } ] -> ()
  | _ -> Alcotest.fail "expected an assignment (one-token lookahead past the ident)");
  (match (prog "print(1)").Ast.stmts with
  | [ Ast.Expr_stmt (Ast.Call ("print", [ _ ], _), _) ] -> ()
  | _ -> Alcotest.fail "expected a print call expression statement")

let test_multi_statement () =
  let stmts = (prog "let a = 6\nvar c = a + 7\nc = c * 2\n").Ast.stmts in
  Alcotest.(check int) "three statements" 3 (List.length stmts);
  match stmts with
  | [ Ast.Let { is_var = false; _ }; Ast.Let { is_var = true; _ }; Ast.Assign _ ] -> ()
  | _ -> Alcotest.fail "expected let; var; assign"

let test_call_args () =
  match expr_of "f(1, 2, 3)" with
  | Ast.Call ("f", [ a; b; c ], _) ->
      Alcotest.(check string) "arg0" "1" (Ast.dump_expr a);
      Alcotest.(check string) "arg1" "2" (Ast.dump_expr b);
      Alcotest.(check string) "arg2" "3" (Ast.dump_expr c)
  | _ -> Alcotest.fail "expected a 3-argument call (comma-separated args)"

let test_errors () =
  Alcotest.(check int) "valid expr: no diagnostics" 0 (ndiags "1 + 2 * 3");
  Alcotest.(check bool) "trailing operator is reported" true (ndiags "1 +" >= 1);
  Alcotest.(check bool) "missing ')' is reported" true (ndiags "print(1" >= 1)

let () =
  Alcotest.run "parser"
    [
      ("precedence", [ Alcotest.test_case "precedence & associativity" `Quick test_precedence_assoc ]);
      ("unary", [ Alcotest.test_case "unary minus" `Quick test_unary ]);
      ("statements", [ Alcotest.test_case "statement kinds" `Quick test_statements ]);
      ("multi", [ Alcotest.test_case "multiple statements" `Quick test_multi_statement ]);
      ("calls", [ Alcotest.test_case "comma-separated args" `Quick test_call_args ]);
      ("errors", [ Alcotest.test_case "diagnostics on malformed input" `Quick test_errors ]);
    ]
