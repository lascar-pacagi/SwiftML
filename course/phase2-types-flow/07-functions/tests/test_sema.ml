(* Alcotest unit tests for concept-07 sema: functions, calls, return, missing-return. *)

let errors (src : string) : string list =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  Diagnostics.all d
  |> List.filter (fun (x : Diagnostics.t) -> x.Diagnostics.severity = Diagnostics.Error)
  |> List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message)

let accepted src = Alcotest.(check (list string)) (Printf.sprintf "accept %S" src) [] (errors src)
let has_error src msg =
  Alcotest.(check bool) (Printf.sprintf "%S => %S" src msg) true (List.mem msg (errors src))

let test_accept () =
  accepted "func add(_ a: Int, _ b: Int) -> Int { return a + b }\nprint(add(1, 2))";
  accepted "func fib(_ n: Int) -> Int {\n  if n < 2 { return n }\n  return fib(n - 1) + fib(n - 2)\n}\nprint(fib(5))";
  accepted "func greet(_ name: String) { print(name) }\ngreet(\"hi\")";
  (* forward reference: a function may be called before its textual declaration *)
  accepted "print(g())\nfunc g() -> Int { return 1 }";
  (* an integer-literal argument coerces to a Double parameter *)
  accepted "func f(_ x: Double) -> Double { return x }\nprint(f(1))"

let test_returns () =
  has_error "func f() -> Int { print(1) }"
    "missing return in function expected to return 'Int'";
  has_error "func f() -> Int { return \"s\" }"
    "cannot convert value of type 'String' to specified type 'Int'";
  has_error "return 1" "'return' invalid outside of a func";
  has_error "func f() { return 1 }" "unexpected non-void return value in void function";
  has_error "func f() -> Int { return }" "non-void function should return a value"

let test_calls () =
  has_error "func f(_ x: Int) -> Int { return x }\nprint(f(\"s\"))"
    "cannot convert value of type 'String' to specified type 'Int'";
  has_error "func f(_ x: Int) -> Int { return x }\nprint(f(1, 2))"
    "function 'f' expects 1 argument(s) but 2 given";
  has_error "nope()" "cannot find 'nope' in scope"

let () =
  Alcotest.run "sema-funcs"
    [
      ("accept", [ Alcotest.test_case "well-typed functions" `Quick test_accept ]);
      ("returns", [ Alcotest.test_case "return & missing-return" `Quick test_returns ]);
      ("calls", [ Alcotest.test_case "call arity & arg types" `Quick test_calls ]);
    ]
