(* Optional §6 exercises. Each group PROBES first: until the exercise is started the group reports
   `skipped — not started`, which `make lab` shows as TODO (optional) — never as a failure. A
   half-done attempt does not skip, so it shows up red, which is the point. Programs are built and
   run in a child process, so a hang in generated code stays bounded. *)

let base_ready_result =
  lazy
    (let result =
       Exercise_test_support.build_and_run
         "enum Color { case red, green }\n\
          let c = Color.green\n\
          print(c == Color.red)"
     in
     result.status = 0 && Exercise_test_support.contains result.stdout "false")

(* the concept's own holes have to be filled before any exercise can be judged *)
let base_ready () = Lazy.force base_ready_result

(* 1 — explicit raw values: `case north = 1` overrides the positional default. *)
let explicit_raw_program =
  "enum Dir: Int {\n\
  \  case north = 10\n\
  \  case south = 20\n\
   }\n\
   print(Dir.north.rawValue)\n\
   print(Dir.south.rawValue)"

let ex1_started () =
  base_ready ()
  && (Exercise_test_support.lab [ "--typecheck" ] explicit_raw_program).status = 0

let test_explicit_raw () =
  let result = Exercise_test_support.build_and_run explicit_raw_program in
  Alcotest.(check int) "an explicit raw enum compiles" 0 result.status;
  Alcotest.(check string) "the written raws are used, not the tags" "10\n20\n" result.stdout;
  let mixed =
    Exercise_test_support.build_and_run
      "enum E: Int {\n\
      \  case a = 5\n\
      \  case b\n\
       }\n\
       print(E.b.rawValue)"
  in
  Alcotest.(check string) "an omitted raw continues from the one before it" "6\n" mixed.stdout

(* 2 — Equatable for associated values: declared conformance makes `==` compare payloads. *)
let equatable_program =
  "enum S: Equatable {\n\
  \  case pair(Int, Int)\n\
   }\n\
   print(S.pair(1, 2) == S.pair(1, 2))\n\
   print(S.pair(1, 2) == S.pair(1, 3))"

let ex2_started () =
  base_ready () && (Exercise_test_support.lab [ "--typecheck" ] equatable_program).status = 0

let test_equatable () =
  let result = Exercise_test_support.build_and_run equatable_program in
  Alcotest.(check int) "a declared conformance compiles" 0 result.status;
  Alcotest.(check string) "every associated value participates" "true\nfalse\n" result.stdout;
  let tags =
    Exercise_test_support.build_and_run
      "enum S: Equatable {\n\
      \  case a(Int)\n\
      \  case b(Int)\n\
       }\n\
       print(S.a(1) == S.b(1))"
  in
  Alcotest.(check string) "different cases are unequal whatever they carry" "false\n" tags.stdout

(* 3 — indirect enums: a recursive case cannot be inline, so its payload is boxed. *)
let indirect_program =
  "indirect enum Expr {\n\
  \  case lit(Int)\n\
  \  case add(Expr, Expr)\n\
   }\n\
   let e = Expr.add(Expr.lit(1), Expr.lit(2))\n\
   print(0)"

let ex3_started () =
  base_ready () && (Exercise_test_support.lab [ "--typecheck" ] indirect_program).status = 0

let test_indirect () =
  let result = Exercise_test_support.build_and_run indirect_program in
  Alcotest.(check int) "a recursive enum compiles and runs" 0 result.status;
  Alcotest.(check string) "and is still a value you can build" "0\n" result.stdout;
  let sized =
    Exercise_test_support.lab [ "--emit-llvm" ] indirect_program
  in
  Alcotest.(check bool)
    "the recursive payload is a pointer, not an inline copy" true
    (Exercise_test_support.contains sized.stdout "ptr")

let () =
  Alcotest.run "exercises-11"
    [
      Exercise_test_support.group "1: explicit raw values" ex1_started test_explicit_raw;
      Exercise_test_support.group "2: Equatable for associated values" ex2_started test_equatable;
      Exercise_test_support.group "3: indirect enums" ex3_started test_indirect;
    ]
