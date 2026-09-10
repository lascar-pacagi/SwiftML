(* Optional §6 exercises. The probes distinguish untouched code from a partial attempt. *)

let diagnostics source =
  let sink = Diagnostics.create () in
  (try
     let program =
       Parser.parse_program
         (Parser.create (Lexer.tokenize (Lexer.create source sink)) sink)
     in
     Sema.check program sink
   with _ -> ());
  Diagnostics.all sink

let messages severity source =
  diagnostics source
  |> List.filter (fun (diagnostic : Diagnostics.t) ->
      diagnostic.Diagnostics.severity = severity)
  |> List.map (fun (diagnostic : Diagnostics.t) ->
      diagnostic.Diagnostics.message)

let errors = messages Diagnostics.Error
let warnings = messages Diagnostics.Warning
let notes = messages Diagnostics.Note

let base_ready () =
  errors "func twice(_ n: Int) -> Int { return n * 2 }\nprint(twice(3))" = []
  && errors "func f() -> Int { print(1) }" <> []

let ex1_started () =
  base_ready ()
  && errors
       "func identity(value: Int) -> Int { return value }\n\
        print(identity(value: 1))"
     = []

let test_argument_labels () =
  Alcotest.(check (list string))
    "a declared label is required" []
    (errors
       "func choose(value: Int, enabled: Bool) -> Int {\n\
       \  if enabled { return value } else { return 0 }\n\
        }\n\
        print(choose(value: 7, enabled: true))");
  Alcotest.(check (list string))
    "underscore keeps an argument positional" []
    (errors
       "func identity(_ value: Int) -> Int { return value }\nprint(identity(1))");
  Alcotest.(check bool)
    "a wrong label names have and expected" true
    (List.mem
       "incorrect argument label in call (have 'wrong:', expected 'value:')"
       (errors
          "func identity(value: Int) -> Int { return value }\n\
           print(identity(wrong: 1))"))

let ex2_started () =
  base_ready () && warnings "func f() {\n  return\n  print(1)\n}" <> []

let test_unreachable_return () =
  Alcotest.(check (list string))
    "after return"
    [ "code after 'return' will never be executed" ]
    (warnings "func f() {\n  return\n  print(1)\n}");
  Alcotest.(check (list string))
    "a conditional return does not make the tail unreachable" []
    (warnings "func f(_ b: Bool) {\n  if b { return }\n  print(1)\n}")

let duplicate = "func f() { }\nfunc f() { }"
let ex3_started () = base_ready () && notes duplicate <> []

let test_redeclaration_notes () =
  Alcotest.(check bool)
    "parameterless spelling" true
    (List.mem "invalid redeclaration of 'f()'" (errors duplicate));
  Alcotest.(check (list string))
    "the first declaration is noted"
    [ "'f()' previously declared here" ]
    (notes duplicate);
  Alcotest.(check bool)
    "parameterized spelling" true
    (List.mem "invalid redeclaration of 'g'"
       (errors "func g(_ x: Int) { }\nfunc g(_ x: Int) { }"));
  Alcotest.(check (list string))
    "mutual recursion still works" []
    (errors
       "func even(_ n: Int) -> Bool {\n\
       \  if n == 0 { return true }\n\
       \  return odd(n - 1)\n\
        }\n\
        func odd(_ n: Int) -> Bool {\n\
       \  if n == 0 { return false }\n\
       \  return even(n - 1)\n\
        }")

let () =
  Alcotest.run "exercises-07"
    [
      Exercise_test_support.group "1: argument labels" ex1_started
        test_argument_labels;
      Exercise_test_support.group "2: unreachable return" ex2_started
        test_unreachable_return;
      Exercise_test_support.group "3: redeclaration notes" ex3_started
        test_redeclaration_notes;
    ]
