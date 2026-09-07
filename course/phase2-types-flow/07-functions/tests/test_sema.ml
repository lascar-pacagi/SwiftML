(* Alcotest unit tests for concept-07 sema: the four TODO(07) holes, one group each, in the
   order they become observable — the two-pass driver runs everything, so it comes first. *)

let errors (src : string) : string list =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Diagnostics.all d
  |> List.filter (fun (x : Diagnostics.t) -> x.Diagnostics.severity = Diagnostics.Error)
  |> List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message)

let accepted src = Alcotest.(check (list string)) (Printf.sprintf "accept %S" src) [] (errors src)

let has_error src msg =
  Alcotest.(check bool) (Printf.sprintf "%S => %S" src msg) true (List.mem msg (errors src))

let error_count src n =
  Alcotest.(check int) (Printf.sprintf "%S => %d error(s)" src n) n (List.length (errors src))

(* ---- the two-pass driver -------------------------------------------------------------- *)

let test_statements_only () =
  accepted "let n = 2\nprint(n * 3)";
  has_error "let x: Int = \"s\"" "cannot convert value of type 'String' to specified type 'Int'"

let test_redeclaration () =
  has_error "func f() { }\nfunc f() { }" "invalid redeclaration of 'f'";
  error_count "func f() { }\nfunc f() { }" 1;
  accepted "func f() { }\nfunc g() { }"

let test_forward_reference () =
  accepted "print(g())\nfunc g() -> Int { return 1 }";
  accepted "func twice(_ n: Int) -> Int { return double(n) }\nfunc double(_ n: Int) -> Int { return n * 2 }"

let test_recursion () =
  accepted "func fib(_ n: Int) -> Int {\n  if n < 2 { return n }\n  return fib(n - 1) + fib(n - 2)\n}\nprint(fib(5))";
  accepted
    "func isEven(_ n: Int) -> Bool {\n  if n == 0 { return true }\n  return isOdd(n - 1)\n}\n\
     func isOdd(_ n: Int) -> Bool {\n  if n == 0 { return false }\n  return isEven(n - 1)\n}"

let test_items_in_order () =
  (* a statement between two declarations is checked in its place *)
  has_error "func a() { }\nlet q: Int = true\nfunc b() { }"
    "cannot convert value of type 'Bool' to specified type 'Int'"

(* ---- check_func ------------------------------------------------------------------------ *)

let test_params_in_scope () =
  accepted "func f(_ a: Int, _ b: Bool) {\n  print(a)\n  print(b)\n}";
  accepted "func f(_ a: Int) -> Int {\n  let a = 2\n  return a\n}"

let test_params_immutable () =
  has_error "func f(_ a: Int) {\n  a = 5\n}" "cannot assign to value: 'a' is a 'let' constant"

let test_fresh_scope () =
  (* a body sees no top-level names, and a parameter does not leak out *)
  has_error "let x = 1\nfunc f() {\n  print(x)\n}" "cannot find 'x' in scope";
  has_error "func f(_ a: Int) { }\nprint(a)" "cannot find 'a' in scope"

let test_unknown_types () =
  has_error "func f(_ a: Nope) { }" "cannot find type 'Nope' in scope";
  has_error "func g() -> Nope { return 1 }" "cannot find type 'Nope' in scope"

let missing = "missing return in global function expected to return 'Int'"

let test_missing_return () =
  has_error "func f() -> Int {\n  print(1)\n  print(2)\n}" missing;
  has_error "func f(_ n: Int) -> Int {\n  if n > 0 { return 1 }\n}" missing;
  has_error "func f(_ n: Int) -> Int {\n  while n > 0 { return 1 }\n}" missing;
  has_error "func f(_ n: Int) -> Int {\n  if n > 0 { return 1 } else { print(0) }\n}" missing;
  has_error "func f(_ n: Int) -> Int {\n  if n > 0 { return 1 } else if n < 0 { return 2 }\n}" missing;
  has_error "func f() -> Bool {\n  print(1)\n}" "missing return in global function expected to return 'Bool'"

let test_definite_return () =
  accepted "func f() {\n  print(1)\n  print(2)\n}";
  accepted "func f(_ n: Int) -> Int {\n  if n > 0 { return 1 } else { return 2 }\n}";
  accepted "func f(_ n: Int) -> Int {\n  if n > 0 { return 1 } else if n < 0 { return 2 } else { return 0 }\n}";
  (* what follows a return is unreachable, so the block still returns *)
  accepted "func g() -> Int {\n  return 1\n  print(2)\n}"

(* ---- return ---------------------------------------------------------------------------- *)

let test_return_outside () =
  has_error "return 1" "return invalid outside of a func";
  has_error "return" "return invalid outside of a func";
  has_error "if true {\n  return 1\n}" "return invalid outside of a func"

let test_return_void () =
  has_error "func f() { return 1 }" "unexpected non-void return value in void function";
  has_error "func f() -> Int { return }" "non-void function should return a value";
  accepted "func f(_ n: Int) {\n  if n == 0 { return }\n  print(n)\n}"

let test_return_type () =
  has_error "func f() -> Int { return \"s\" }"
    "cannot convert value of type 'String' to specified type 'Int'";
  has_error "func f() -> Bool { return 1 }"
    "cannot convert value of type 'Int' to specified type 'Bool'";
  (* the return type is the contextual type: an integer literal coerces to Double *)
  accepted "func f() -> Double { return 1 }";
  accepted "func f(_ n: Int) -> Int {\n  let m = n * 2\n  return m + n\n}";
  error_count "func f(_ n: Int) -> Int {\n  if n > 0 { return true }\n  return \"no\"\n}" 2

(* ---- calls ----------------------------------------------------------------------------- *)

let test_call_result () =
  accepted "func add(_ a: Int, _ b: Int) -> Int { return a + b }\nlet s: Int = add(1, 2)";
  accepted "func inc(_ n: Int) -> Int { return n + 1 }\nprint(inc(inc(1)))";
  accepted "func pos(_ n: Int) -> Bool { return n > 0 }\nif pos(1) { print(1) }";
  accepted "func hello() { print(1) }\nhello()";
  has_error "func f() -> Int { return 1 }\nlet s: String = f()"
    "cannot convert value of type 'Int' to specified type 'String'";
  has_error "func f() { }\nlet v: Int = f()"
    "cannot convert value of type '()' to specified type 'Int'"

let test_call_arity () =
  has_error "func f(_ x: Int) -> Int { return x }\nprint(f(1, 2))"
    "function 'f' expects 1 argument(s) but 2 given";
  has_error "func f(_ x: Int) -> Int { return x }\nprint(f())"
    "function 'f' expects 1 argument(s) but 0 given";
  has_error "func f() -> Int { return 1 }\nprint(f(1))"
    "function 'f' expects 0 argument(s) but 1 given";
  (* on an arity error the arguments are not checked: one message, not three *)
  error_count "func f(_ x: Int) -> Int { return x }\nprint(f(\"a\", \"b\"))" 1

let test_call_args () =
  has_error "func f(_ x: Int) -> Int { return x }\nprint(f(\"s\"))"
    "cannot convert value of type 'String' to specified type 'Int'";
  error_count "func f(_ a: Int, _ b: Bool) { }\nf(true, 1)" 2;
  (* an integer literal argument coerces to a Double parameter *)
  accepted "func f(_ x: Double) -> Double { return x }\nprint(f(1))";
  has_error "nope()" "cannot find 'nope' in scope"

(* ---- the definite-return analysis, on its own ------------------------------------------- *)

(* `Sema.block_returns` is a pure function of the AST, so these build statements directly
   instead of parsing source: the group grades that one hole and nothing else — it passes with
   every other TODO in sema.ml still raising. *)
let sp = Token.dummy_span
let e = Ast.Int_lit (1, sp)
let ret = Ast.Return (Some e, sp)
let bare_ret = Ast.Return (None, sp)
let noise = Ast.Expr_stmt (e, sp)
let if_ c t el = Ast.If { cond = c; then_blk = t; else_blk = el; span = sp }
let while_ b = Ast.While { cond = Ast.Bool_lit (true, sp); body = b; span = sp }
let for_ b = Ast.For { var = "i"; lo = e; hi = e; body = b; span = sp }

let returns what expected stmts =
  Alcotest.(check bool) what expected (Sema.block_returns stmts)

let test_ret_plain () =
  returns "an empty block returns nothing" false [];
  returns "a block of one `return`" true [ ret ];
  returns "a bare `return` counts too" true [ bare_ret ];
  returns "statements with no return" false [ noise; noise ]

let test_ret_after () =
  (* whatever follows a return is unreachable, so the block still returns *)
  returns "`return` then a statement" true [ ret; noise ];
  returns "a statement then `return`" true [ noise; ret ]

let test_ret_if () =
  returns "`if` with no else" false [ if_ e [ ret ] None ];
  returns "`if`/`else`, both return" true [ if_ e [ ret ] (Some [ ret ]) ];
  returns "`if`/`else`, only then returns" false [ if_ e [ ret ] (Some [ noise ]) ];
  returns "`if`/`else`, only else returns" false [ if_ e [ noise ] (Some [ ret ]) ]

let test_ret_chain () =
  (* an `else if` is an If in the else block — the recursion is what handles it *)
  let chain last = if_ e [ ret ] (Some [ if_ e [ ret ] last ]) in
  returns "`else if` ending in a returning else" true [ chain (Some [ ret ]) ];
  returns "`else if` with no final else" false [ chain None ]

let test_ret_loops () =
  (* the trap: a loop body may never run, so a `return` inside one proves nothing *)
  returns "`while` holding a return" false [ while_ [ ret ] ];
  returns "`for` holding a return" false [ for_ [ ret ] ];
  returns "a loop, then a return" true [ while_ [ noise ]; ret ]

let () =
  Alcotest.run "sema-funcs"
    [
      ( "definite return",
        [
          Alcotest.test_case "a block of returns" `Quick test_ret_plain;
          Alcotest.test_case "what follows a return" `Quick test_ret_after;
          Alcotest.test_case "if needs both branches" `Quick test_ret_if;
          Alcotest.test_case "an else-if chain" `Quick test_ret_chain;
          Alcotest.test_case "a loop never counts" `Quick test_ret_loops;
        ] );
      ( "passes",
        [
          Alcotest.test_case "statements only; top level" `Quick test_statements_only;
          Alcotest.test_case "redeclaration" `Quick test_redeclaration;
          Alcotest.test_case "forward reference" `Quick test_forward_reference;
          Alcotest.test_case "recursion; mutual recursion" `Quick test_recursion;
          Alcotest.test_case "items checked in order" `Quick test_items_in_order;
        ] );
      ( "check_func",
        [
          Alcotest.test_case "params in scope; shadowing" `Quick test_params_in_scope;
          Alcotest.test_case "params are let" `Quick test_params_immutable;
          Alcotest.test_case "fresh scope, no leak" `Quick test_fresh_scope;
          Alcotest.test_case "unknown param/return type" `Quick test_unknown_types;
          Alcotest.test_case "missing return" `Quick test_missing_return;
          Alcotest.test_case "definite return accepted" `Quick test_definite_return;
        ] );
      ( "return",
        [
          Alcotest.test_case "outside a func" `Quick test_return_outside;
          Alcotest.test_case "void vs non-void" `Quick test_return_void;
          Alcotest.test_case "against the return type" `Quick test_return_type;
        ] );
      ( "calls",
        [
          Alcotest.test_case "result type" `Quick test_call_result;
          Alcotest.test_case "arity" `Quick test_call_arity;
          Alcotest.test_case "argument types" `Quick test_call_args;
        ] );
    ]
