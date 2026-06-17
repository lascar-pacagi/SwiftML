(* Alcotest unit tests for concept-07 parser additions: function declarations (with the
   optional `_` external label), return statements, and top-level items. *)

let prog (src : string) : Ast.program =
  let d = Diagnostics.create () in
  Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d)

let dump src = Ast.dump_program (prog src)
let check name expected src = Alcotest.(check string) name expected (dump src)

let test_func () =
  check "func with ret" "(func add (a:Int b:Int) -> Int ((return (+ a b))))"
    "func add(_ a: Int, _ b: Int) -> Int { return a + b }";
  check "void func, no params" "(func g () ((print 1)))" "func g() { print(1) }";
  (* a labelled parameter `a: Int` keeps the name; the label is dropped in our model *)
  check "labelled param" "(func h (x:Int) -> Int ((return x)))"
    "func h(x: Int) -> Int { return x }"

let test_return () =
  check "return value" "(return 5)" "return 5";
  check "bare return" "(return)" "return"

let test_items () =
  (* a program interleaves function declarations and top-level statements *)
  check "func then stmt" "(func f () -> Int ((return 1)))\n(print (f ))" "func f() -> Int { return 1 }\nprint(f())"

let () =
  Alcotest.run "parser-funcs"
    [
      ("func", [ Alcotest.test_case "function declarations" `Quick test_func ]);
      ("return", [ Alcotest.test_case "return statements" `Quick test_return ]);
      ("items", [ Alcotest.test_case "top-level items" `Quick test_items ]);
    ]
