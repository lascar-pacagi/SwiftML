(* Optional §6 exercises. These are black-box tests because two exercises deliberately
   change the driver and linked runtime, not just IRGen. Each child process has a deadline. *)

let base_ready_result =
  lazy
    (let result = Exercise_test_support.lab [ "--emit-llvm" ] "print(6 * 7)" in
     result.status = 0
     && Exercise_test_support.contains result.stdout "ret i32 0")

let base_ready () = Lazy.force base_ready_result

let initialized_program =
  "var answer: Int\nif true { answer = 7 } else { answer = 9 }\nprint(answer)"

let uninitialized_program =
  "var answer: Int\nif true { answer = 7 }\nprint(answer)"

let typecheck source = Exercise_test_support.lab [ "--emit-llvm" ] source

let ex1_started () =
  base_ready ()
  &&
  let parsed =
    Exercise_test_support.lab [ "--emit-ast" ] "var answer: Int\nanswer = 7"
  in
  parsed.status = 0

let test_definite_initialization () =
  let good = Exercise_test_support.build_and_run initialized_program in
  Alcotest.(check int) "all incoming paths initialize" 0 good.status;
  Alcotest.(check string) "the initialized value runs" "7\n" good.stdout;
  let bad = typecheck uninitialized_program in
  Alcotest.(check bool) "one missing path is rejected" true (bad.status <> 0);
  Alcotest.(check bool)
    "the diagnostic names the variable" true
    (Exercise_test_support.contains bad.stderr
       "variable 'answer' used before being initialized");
  let straight_line =
    Exercise_test_support.build_and_run
      "var value: Int\nvalue = 3\nprint(value)"
  in
  Alcotest.(check int) "a preceding store initializes" 0 straight_line.status;
  Alcotest.(check string) "straight-line result" "3\n" straight_line.stdout

let ex2_started () =
  base_ready ()
  &&
  let result = Exercise_test_support.build_and_run "print(1.0)" in
  result.status = 0 && result.stdout <> "1\n"

let test_double_output () =
  let check source expected =
    let result = Exercise_test_support.build_and_run source in
    Alcotest.(check int) source 0 result.status;
    Alcotest.(check string) source expected result.stdout
  in
  check "print(1.0)" "1.0\n";
  check "print(0.1)" "0.1\n";
  check "print(0.1 + 0.2)" "0.30000000000000004\n"

let integer_ir () = Exercise_test_support.lab [ "--emit-llvm" ] "print(42)"

let ex3_started () =
  base_ready ()
  &&
  let result = integer_ir () in
  result.status = 0
  && Exercise_test_support.contains result.stdout "call void @swiftml_print_int"

let test_runtime () =
  let ir = integer_ir () in
  Alcotest.(check int) "IR generation succeeds" 0 ir.status;
  Alcotest.(check bool)
    "integer print calls the runtime" true
    (Exercise_test_support.contains ir.stdout "call void @swiftml_print_int");
  Alcotest.(check bool)
    "integer print no longer calls printf directly" false
    (Exercise_test_support.contains ir.stdout
       "call i32 (ptr, ...) @printf(ptr @.fmt, i64");
  let result = Exercise_test_support.build_and_run "print(42)" in
  Alcotest.(check int) "runtime.c links" 0 result.status;
  Alcotest.(check string) "linked runtime prints" "42\n" result.stdout

let () =
  Alcotest.run "exercises-09"
    [
      Exercise_test_support.group "1: definite initialization" ex1_started
        test_definite_initialization;
      Exercise_test_support.group "2: Double output" ex2_started
        test_double_output;
      Exercise_test_support.group "3: tiny runtime" ex3_started test_runtime;
    ]
