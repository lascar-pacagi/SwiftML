(* Optional §6 exercises. Tests run complete programs so method/getter lowering remains an
   implementation choice. The child-process helper keeps parser and generated-code hangs bounded. *)

let base_ready_result =
  lazy
    (let result =
       Exercise_test_support.lab [ "--emit-llvm" ]
         "struct Pair { var first: Int; var second: Int }\n\
          let pair = Pair(first: 20, second: 22)\n\
          print(pair.first + pair.second)"
     in
     result.status = 0
     && Exercise_test_support.contains result.stdout "%Pair = type { i64, i64 }")

let base_ready () = Lazy.force base_ready_result

let methods_program =
  "struct Counter {\n\
  \  var value: Int\n\
  \  func read() -> Int { return self.value }\n\
  \  mutating func increment() { self.value = self.value + 1 }\n\
   }\n\
   var counter = Counter(value: 1)\n\
   counter.increment()\n\
   print(counter.read())"

let ex1_started () =
  base_ready ()
  &&
  let result = Exercise_test_support.lab [ "--emit-tokens" ] "mutating" in
  result.status = 0 && Exercise_test_support.contains result.stdout "mutating\n"

let test_methods () =
  let result = Exercise_test_support.build_and_run methods_program in
  Alcotest.(check int) "methods compile and run" 0 result.status;
  Alcotest.(check string) "mutating self writes back" "2\n" result.stdout;
  let read_only =
    Exercise_test_support.build_and_run
      "struct Box {\n\
      \  var value: Int\n\
      \  func read() -> Int { return self.value }\n\
       }\n\
       let box = Box(value: 7)\n\
       print(box.read())"
  in
  Alcotest.(check int)
    "a let value can call a read-only method" 0 read_only.status;
  Alcotest.(check string) "read-only result" "7\n" read_only.stdout;
  let mutating_let =
    Exercise_test_support.lab [ "--typecheck" ]
      "struct Box {\n\
      \  var value: Int\n\
      \  mutating func clear() { self.value = 0 }\n\
       }\n\
       let box = Box(value: 7)\n\
       box.clear()"
  in
  Alcotest.(check bool)
    "a let value cannot call a mutating method" true (mutating_let.status <> 0)

let computed_program =
  "struct Rectangle {\n\
  \  var width: Int\n\
  \  var height: Int\n\
  \  var area: Int { return self.width * self.height }\n\
   }\n\
   let rectangle = Rectangle(width: 6, height: 7)\n\
   print(rectangle.area)"

let ex2_started () =
  base_ready ()
  &&
  let result = Exercise_test_support.lab [ "--emit-ast" ] computed_program in
  result.status = 0

let test_computed_properties () =
  let result = Exercise_test_support.build_and_run computed_program in
  Alcotest.(check int) "a computed property compiles" 0 result.status;
  Alcotest.(check string) "the getter computes its value" "42\n" result.stdout;
  let ir = Exercise_test_support.lab [ "--emit-llvm" ] computed_program in
  Alcotest.(check bool)
    "the layout contains only the two stored fields" true
    (Exercise_test_support.contains ir.stdout "%Rectangle = type { i64, i64 }")

let equatable_program =
  "struct Pair { var first: Int; var second: Bool }\n\
   let a = Pair(first: 1, second: true)\n\
   let b = Pair(first: 1, second: true)\n\
   let c = Pair(first: 2, second: true)\n\
   print(a == b)\n\
   print(a == c)"

let ex3_started () =
  base_ready ()
  &&
  let result = Exercise_test_support.lab [ "--typecheck" ] equatable_program in
  result.status = 0

let test_equatable () =
  let result = Exercise_test_support.build_and_run equatable_program in
  Alcotest.(check int) "struct equality compiles" 0 result.status;
  Alcotest.(check string)
    "every field participates" "true\nfalse\n" result.stdout;
  let bool_differs =
    Exercise_test_support.build_and_run
      "struct Pair { var first: Int; var second: Bool }\n\
       let a = Pair(first: 1, second: true)\n\
       let b = Pair(first: 1, second: false)\n\
       print(a == b)"
  in
  Alcotest.(check string)
    "a later field participates too" "false\n" bool_differs.stdout

let () =
  Alcotest.run "exercises-10"
    [
      Exercise_test_support.group "1: methods and mutating" ex1_started
        test_methods;
      Exercise_test_support.group "2: computed properties" ex2_started
        test_computed_properties;
      Exercise_test_support.group "3: Equatable" ex3_started test_equatable;
    ]
