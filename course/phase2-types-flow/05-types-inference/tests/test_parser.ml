(* Alcotest unit tests for the concept-05 parser additions: the new literal prefixes,
   type annotations, and the comparison operators (precedence below arithmetic). *)

let prog (src : string) : Ast.program =
  let d = Diagnostics.create () in
  Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d)

let expr_of src =
  match (prog src).Ast.stmts with
  | [ Ast.Expr_stmt (e, _) ] -> e
  | _ -> Alcotest.fail "expected one expression statement"

let dump src = Ast.dump_expr (expr_of src)
let check_dump name expected src = Alcotest.(check string) name expected (dump src)
let stmt_dump src = Ast.dump_program (prog src)

let test_literals () =
  check_dump "double literal" "3.14" "3.14";
  check_dump "bool literal" "true" "true";
  check_dump "string literal" "\"hi\"" "\"hi\""

let test_annotations () =
  Alcotest.(check string) "annotated let" "(let d : Double 3.14)" (stmt_dump "let d: Double = 3.14");
  Alcotest.(check string) "unannotated let" "(let x 1)" (stmt_dump "let x = 1")

let test_comparisons () =
  check_dump "==" "(== 1 2)" "1 == 2";
  check_dump "<=" "(<= 1 2)" "1 <= 2";
  (* comparisons bind looser than arithmetic: 1 + 2 < 3 * 4  =>  ((1+2) < (3*4)) *)
  check_dump "precedence vs arithmetic" "(< (+ 1 2) (* 3 4))" "1 + 2 < 3 * 4"

let () =
  Alcotest.run "parser-types"
    [
      ("literals", [ Alcotest.test_case "new literal prefixes" `Quick test_literals ]);
      ("annotations", [ Alcotest.test_case "type annotations" `Quick test_annotations ]);
      ("comparisons", [ Alcotest.test_case "comparison operators + precedence" `Quick test_comparisons ]);
    ]
