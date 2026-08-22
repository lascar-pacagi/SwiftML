(* Alcotest unit tests for the concept-05 type checker. Run the front end in-process and
   assert the exact diagnostics (and that well-typed programs produce none). The cram test
   + the swiftc type-check oracle cover end-to-end accept/reject; these pin the messages.

   RED until lexer/parser/sema are implemented; GREEN against the solutions. *)

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

let test_accept () =
  accepted "let x = 1";
  accepted "let d: Double = 1 + 2";
  (* coercion through arithmetic *)
  accepted "let e = 1 + 2.0";
  (* integer literal flexes to Double *)
  accepted "let s = \"hi\"\nprint(s)";
  accepted "let b = 1 < 2";
  accepted "var n = 1\nn = 2";
  accepted "let p: Bool = 1 == 1"

let test_mismatch () =
  has_error "let x: Int = \"s\"" "cannot convert value of type 'String' to specified type 'Int'";
  has_error "let i = 1\nlet d: Double = i"
    "cannot convert value of type 'Int' to specified type 'Double'";
  has_error "var n = 1\nn = 2.0" "cannot convert value of type 'Double' to specified type 'Int'"

let test_operators () =
  has_error "let y = 1 + true"
    "binary operator '+' cannot be applied to operands of type 'Int' and 'Bool'";
  has_error "let b = 1 == \"a\""
    "binary operator '==' cannot be applied to operands of type 'Int' and 'String'";
  has_error "let b = true < false"
    "binary operator '<' cannot be applied to operands of type 'Bool' and 'Bool'"

let test_scope () =
  has_error "print(nope)" "cannot find 'nope' in scope";
  has_error "let x: Foo = 1" "cannot find type 'Foo' in scope";
  has_error "let k = 1\nk = 2" "cannot assign to value: 'k' is a 'let' constant"

let () =
  Alcotest.run "sema-types"
    [
      ("accept", [ Alcotest.test_case "well-typed programs" `Quick test_accept ]);
      ("annotations", [ Alcotest.test_case "type mismatches" `Quick test_mismatch ]);
      ("operators", [ Alcotest.test_case "operator typing" `Quick test_operators ]);
      ("scope", [ Alcotest.test_case "names & types in scope" `Quick test_scope ]);
    ]
