(* Alcotest unit tests for concept-06 sema: control-flow type rules. *)

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
  accepted "var n = 0\nwhile n < 3 { n = n + 1 }\nprint(n)";
  accepted "let x = 5\nif x < 0 { print(x) } else if x == 0 { print(0) } else { print(1) }";
  accepted "for i in 0 ..< 10 { print(i) }";
  accepted "let a = true\nlet b = false\nif a && b || a { print(1) }";
  accepted "for i in 0 ..< 5 {\n  if i == 2 { continue }\n  if i == 4 { break }\n}"

let test_conditions () =
  has_error "if 1 { print(1) }" "cannot convert value of type 'Int' to specified type 'Bool'";
  has_error "while 3 { print(1) }" "cannot convert value of type 'Int' to specified type 'Bool'";
  has_error "let b = 1 && true"
    "binary operator '&&' cannot be applied to operands of type 'Int' and 'Bool'"

let test_loops () =
  has_error "break" "'break' is only allowed inside a loop";
  has_error "continue" "'continue' is only allowed inside a loop";
  has_error "for i in 0 ..< 3 { i = 9 }" "cannot assign to value: 'i' is a 'let' constant";
  has_error "for i in 0 ..< 3.5 { print(i) }"
    "cannot convert value of type 'Double' to specified type 'Int'"

let test_scope () =
  (* a binding made inside a block does not leak out of it *)
  has_error "if true { let z = 1 }\nprint(z)" "cannot find 'z' in scope";
  (* but the outer scope is visible inside the block *)
  accepted "let outer = 1\nif true { print(outer) }"

let () =
  Alcotest.run "sema-flow"
    [
      ("accept", [ Alcotest.test_case "well-typed control flow" `Quick test_accept ]);
      ("conditions", [ Alcotest.test_case "Bool conditions & logical ops" `Quick test_conditions ]);
      ("loops", [ Alcotest.test_case "loop var, ranges, break/continue" `Quick test_loops ]);
      ("scope", [ Alcotest.test_case "lexical block scope" `Quick test_scope ]);
    ]
