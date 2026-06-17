(* Alcotest unit tests for concept-06 parser additions: control-flow statements, blocks,
   and the &&/|| precedence (below comparisons; && above ||). *)

let prog (src : string) : Ast.program =
  let d = Diagnostics.create () in
  Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d)

let stmt_dump src = Ast.dump_program (prog src)
let check name expected src = Alcotest.(check string) name expected (stmt_dump src)

let expr_of src =
  match (prog src).Ast.stmts with
  | [ Ast.Expr_stmt (e, _) ] -> e
  | _ -> Alcotest.fail "expected one expression statement"

let test_if () =
  check "if/else" "(if a ((print 1)) ((print 2)))" "if a { print(1) } else { print(2) }";
  check "if only" "(if a ((print 1)))" "if a { print(1) }";
  (* `else if` is an else-block containing one If, so dump_block adds a paren level *)
  check "else if chains" "(if a ((print 1)) ((if b ((print 2)))))"
    "if a { print(1) } else if b { print(2) }"

let test_loops () =
  check "while" "(while a ((print 1)))" "while a { print(1) }";
  check "for in range" "(for i 0 10 ((print i)))" "for i in 0 ..< 10 { print(i) }";
  check "break" "break" "break";
  check "continue" "continue" "continue"

let test_logical_precedence () =
  (* && binds tighter than ||, both looser than comparison *)
  Alcotest.(check string) "&& over ||" "(|| (&& a b) c)" (Ast.dump_expr (expr_of "a && b || c"));
  Alcotest.(check string) "compare over &&" "(&& (< x 1) b)"
    (Ast.dump_expr (expr_of "x < 1 && b"))

let () =
  Alcotest.run "parser-flow"
    [
      ("if", [ Alcotest.test_case "if / else / else-if" `Quick test_if ]);
      ("loops", [ Alcotest.test_case "while / for / break / continue" `Quick test_loops ]);
      ("precedence", [ Alcotest.test_case "&& / || precedence" `Quick test_logical_precedence ]);
    ]
