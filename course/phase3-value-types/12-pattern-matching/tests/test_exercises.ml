(* Optional §6 exercises. Each group PROBES first: until the exercise is started the group reports
   `skipped — not started`, which `make lab` shows as TODO (optional) — never as a failure. A
   half-done attempt does not skip, so it shows up red, which is the point. Programs are built and
   run in a child process, so a hang in generated code stays bounded. *)

let base_ready_result =
  lazy
    (let result =
       Exercise_test_support.build_and_run
         "enum S { case c(Int), dot }\n\
          func f(_ s: S) -> Int {\n\
         \  switch s {\n\
         \  case .c(let r): return r\n\
         \  case .dot: return 0\n\
         \  }\n\
          }\n\
          print(f(S.c(7)))"
     in
     result.status = 0 && Exercise_test_support.contains result.stdout "7")

(* the concept's own holes have to be filled before any exercise can be judged *)
let base_ready () = Lazy.force base_ready_result

(* 1 — `where`: the arm matches only if the pattern binds AND the guard holds. *)
let where_program =
  "enum S { case c(Int) }\n\
   func f(_ s: S) -> Int {\n\
  \  switch s {\n\
  \  case .c(let r) where r > 10: return 1\n\
  \  case .c(let r) where r > 0: return 2\n\
  \  default: return 3\n\
  \  }\n\
   }\n\
   print(f(S.c(50)))\n\
   print(f(S.c(5)))\n\
   print(f(S.c(-1)))"

let ex1_started () =
  base_ready () && (Exercise_test_support.lab [ "--typecheck" ] where_program).status = 0

let test_where () =
  let result = Exercise_test_support.build_and_run where_program in
  Alcotest.(check int) "guarded arms compile" 0 result.status;
  Alcotest.(check string)
    "a failed guard falls through to the next arm, not out of the switch" "1\n2\n3\n"
    result.stdout

(* 2 — `if case`: a one-case switch, desugared onto the same dispatch. *)
let if_case_program =
  "enum S { case c(Int), dot }\n\
   func f(_ s: S) -> Int {\n\
  \  if case .c(let r) = s {\n\
  \    return r\n\
  \  }\n\
  \  return 0\n\
   }\n\
   print(f(S.c(9)))\n\
   print(f(S.dot))"

let ex2_started () =
  base_ready () && (Exercise_test_support.lab [ "--typecheck" ] if_case_program).status = 0

let test_if_case () =
  let result = Exercise_test_support.build_and_run if_case_program in
  Alcotest.(check int) "`if case` compiles" 0 result.status;
  Alcotest.(check string) "it binds on a match and is skipped otherwise" "9\n0\n" result.stdout

(* 3 — tuple patterns: match position-wise, recursing into sub-patterns. *)
let tuple_program =
  "func f(_ a: Int, _ b: Int) -> Int {\n\
  \  switch (a, b) {\n\
  \  case (0, let y): return y\n\
  \  case (let x, 0): return x\n\
  \  default: return -1\n\
  \  }\n\
   }\n\
   print(f(0, 5))\n\
   print(f(7, 0))\n\
   print(f(1, 1))"

let ex3_started () =
  base_ready () && (Exercise_test_support.lab [ "--typecheck" ] tuple_program).status = 0

let test_tuple () =
  let result = Exercise_test_support.build_and_run tuple_program in
  Alcotest.(check int) "tuple patterns compile" 0 result.status;
  Alcotest.(check string) "each position matches independently" "5\n7\n-1\n" result.stdout

(* 4 — a jump table: one LLVM `switch` instead of a chain of comparisons. *)
let table_program =
  "enum S { case a, b, c, d }\n\
   func f(_ s: S) -> Int {\n\
  \  switch s {\n\
  \  case .a: return 0\n\
  \  case .b: return 1\n\
  \  case .c: return 2\n\
  \  case .d: return 3\n\
  \  }\n\
   }\n\
   print(f(S.c))"

(* the only exercise whose evidence is in the IR rather than the source: the chain is gone *)
let ex4_started () =
  base_ready ()
  &&
  let ir = Exercise_test_support.lab [ "--emit-llvm" ] table_program in
  ir.status = 0 && Exercise_test_support.contains ir.stdout "switch i64"

let test_jump_table () =
  let ir = Exercise_test_support.lab [ "--emit-llvm" ] table_program in
  Alcotest.(check bool)
    "the tag selects a block in one instruction" true
    (Exercise_test_support.contains ir.stdout "switch i64");
  let result = Exercise_test_support.build_and_run table_program in
  Alcotest.(check int) "and the program still runs" 0 result.status;
  Alcotest.(check string) "with the same answer the chain gave" "2\n" result.stdout

let () =
  Alcotest.run "exercises-12"
    [
      Exercise_test_support.group "1: where clauses" ex1_started test_where;
      Exercise_test_support.group "2: if case / guard case" ex2_started test_if_case;
      Exercise_test_support.group "3: tuple patterns" ex3_started test_tuple;
      Exercise_test_support.group "4: jump table" ex4_started test_jump_table;
    ]
