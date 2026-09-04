(* Alcotest unit tests for concept-07's lexer and parser holes: the `->` arrow, the `return`
   statement, parameter lists (with the external label dropped), function declarations, and
   top-level items. One group per hole. *)

let tokens (src : string) : Token.kind list =
  let d = Diagnostics.create () in
  Lexer.tokenize (Lexer.create src d) |> List.map (fun (t : Token.t) -> t.Token.kind)

let prog (src : string) : Ast.program =
  let d = Diagnostics.create () in
  Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d)

let diagnostics (src : string) : string list =
  let d = Diagnostics.create () in
  ignore (Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d));
  Diagnostics.all d |> List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message)

let dump src = Ast.dump_program (prog src)
let check name expected src = Alcotest.(check string) name expected (dump src)

let first_error src msg =
  Alcotest.(check (option string)) (Printf.sprintf "%S first error" src) (Some msg)
    (List.nth_opt (diagnostics src) 0)

(* ---- lexer: the arrow ------------------------------------------------------------------ *)

let test_arrow () =
  let kinds src = List.filter (fun k -> k <> Token.Newline && k <> Token.Eof) (tokens src) in
  let has src k =
    Alcotest.(check bool) (Printf.sprintf "%S lexes %s" src (Token.string_of_kind k)) true
      (List.mem k (kinds src))
  in
  has "-> Int" Token.Arrow;
  has "a->b" Token.Arrow;
  Alcotest.(check int) "`a->-b`: one arrow, one minus" 2
    (List.length (List.filter (fun k -> k = Token.Arrow || k = Token.Minus) (kinds "a->-b")));
  (* a `-` not followed by `>` is still minus, and `- >` is two tokens *)
  Alcotest.(check bool) "`a - b` has no arrow" false (List.mem Token.Arrow (kinds "a - b"));
  Alcotest.(check bool) "`- >` has no arrow" false (List.mem Token.Arrow (kinds "a - > b"));
  Alcotest.(check bool) "`- >` is minus then greater" true
    (List.mem Token.Minus (kinds "a - > b") && List.mem Token.Gt (kinds "a - > b"))

(* ---- parser: return -------------------------------------------------------------------- *)

let test_return () =
  check "return value" "(return 5)" "return 5";
  check "return expression" "(return (+ (fib (- n 1)) 2))" "return fib(n - 1) + 2";
  check "bare return, newline" "(return)\n(print 1)" "return\nprint(1)";
  check "bare return, eof" "(return)" "return";
  check "bare return before }" "(if c ((return)))" "if c { return }";
  check "return in a block" "(if c ((print 1) (return x)))" "if c {\n  print(1)\n  return x\n}"

(* ---- parser: parameter lists ----------------------------------------------------------- *)

let test_params () =
  check "empty" "(func f () ())" "func f() { }";
  check "one, `_` label dropped" "(func f (a:Int) ())" "func f(_ a: Int) { }";
  check "three, in order" "(func f (a:Int b:Bool c:String) ())"
    "func f(_ a: Int, _ b: Bool, _ c: String) { }";
  check "no label at all" "(func f (x:Int) ())" "func f(x: Int) { }";
  check "named label dropped" "(func f (start:Int) ())" "func f(from start: Int) { }"

let test_params_errors () =
  first_error "func f { }" "expected '('";
  first_error "func f(a:) { }" "expected a parameter type";
  first_error "func f(a: Int { }" "expected ')'";
  first_error "func f(a: Int,) { }" "expected a parameter name"

(* ---- parser: function declarations ----------------------------------------------------- *)

let test_func () =
  check "func with ret" "(func add (a:Int b:Int) -> Int ((return (+ a b))))"
    "func add(_ a: Int, _ b: Int) -> Int { return a + b }";
  check "void func, no params" "(func g () ((print 1)))" "func g() { print(1) }";
  check "multi-line body"
    "(func f (n:Int) -> Int ((if (< n 2) ((return n))) (return (f (- n 1)))))"
    "func f(_ n: Int) -> Int {\n  if n < 2 {\n    return n\n  }\n  return f(n - 1)\n}";
  check "empty body" "(func nop () ())" "func nop() { }"

let test_func_errors () =
  first_error "func () { }" "expected a function name";
  first_error "func f() -> { }" "expected a return type";
  first_error "func f() -> Int\nprint(1)" "expected '{'";
  first_error "func f() {\n  print(1)\n" "expected '}'"

let test_items () =
  (* a program interleaves function declarations and top-level statements, in order *)
  check "func then stmt" "(func f () -> Int ((return 1)))\n(print (f ))"
    "func f() -> Int { return 1 }\nprint(f())";
  check "stmt, func, stmt, func" "(print (g ))\n(func g () -> Int ((return 1)))\n(let x (g ))\n(func h () ())"
    "print(g())\nfunc g() -> Int { return 1 }\nlet x = g()\nfunc h() { }";
  check "blank line between funcs" "(func a () ())\n(func b () -> Bool ((return true)))"
    "func a() { }\n\nfunc b() -> Bool {\n  return true\n}"

let () =
  Alcotest.run "parser-funcs"
    [
      ("arrow", [ Alcotest.test_case "-> vs - vs - >" `Quick test_arrow ]);
      ("return", [ Alcotest.test_case "with and without a value" `Quick test_return ]);
      ( "params",
        [
          Alcotest.test_case "lists, labels dropped" `Quick test_params;
          Alcotest.test_case "first error of a bad list" `Quick test_params_errors;
        ] );
      ( "func",
        [
          Alcotest.test_case "declarations" `Quick test_func;
          Alcotest.test_case "first error of a bad decl" `Quick test_func_errors;
        ] );
      ("items", [ Alcotest.test_case "top-level items in order" `Quick test_items ]);
    ]
