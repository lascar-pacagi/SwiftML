(* Alcotest unit tests for sema (concept 03).

   These run the front end (lex → parse → sema) in-process and assert the *exact*
   diagnostic messages (and that valid programs produce none) — stronger than the cram
   test, which only greps a substring of one message.

   RED until you implement `sema.ml : check`; GREEN against `solution/sema.ml`. *)

let sema_errors (src : string) : string list =
  let diags = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) diags) in
  Sema.check p diags;
  Diagnostics.all diags
  |> List.filter (fun (d : Diagnostics.t) -> d.Diagnostics.severity = Diagnostics.Error)
  |> List.map (fun (d : Diagnostics.t) -> d.Diagnostics.message)

let has_error src msg =
  Alcotest.(check bool)
    (Printf.sprintf "%S reports %S" src msg)
    true
    (List.mem msg (sema_errors src))

let accepted src =
  Alcotest.(check (list string)) (Printf.sprintf "%S is accepted" src) [] (sema_errors src)

let test_accept () =
  accepted "let a = 2\nvar c = a + 1\nc = c * a\nprint(c)";
  accepted "var v = 1\nv = 2";
  (* a var may be reassigned *)
  accepted "let x = 1\nlet y = x + x\nprint(y)"

let test_undeclared () =
  has_error "print(y)" "cannot find 'y' in scope";
  has_error "x = 5" "cannot find 'x' in scope";
  (* assign to undeclared *)
  has_error "let a = a" "cannot find 'a' in scope";
  (* used in its own initializer *)
  has_error "print(z)\nlet z = 1" "cannot find 'z' in scope"

(* used before declaration *)

let test_immutability () =
  has_error "let k = 1\nk = 2" "cannot assign to value: 'k' is a 'let' constant"

let test_print_arity () = has_error "print(1, 2)" "print(_:) expects exactly one argument"

let () =
  Alcotest.run "sema"
    [
      ("accept", [ Alcotest.test_case "valid programs have no errors" `Quick test_accept ]);
      ("scope", [ Alcotest.test_case "undeclared / use-before-decl" `Quick test_undeclared ]);
      ("immutability", [ Alcotest.test_case "assign to a let constant" `Quick test_immutability ]);
      ("calls", [ Alcotest.test_case "print arity" `Quick test_print_arity ]);
    ]
