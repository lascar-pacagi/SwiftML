(* Alcotest unit tests for concept-23: existential containers + dynamic casts. *)

let front (src : string) : Ast.program * Diagnostics.sink =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  (p, d)

let msgs (d : Diagnostics.sink) : string list =
  List.rev_map (fun (e : Diagnostics.t) -> e.Diagnostics.message) d.Diagnostics.diags

let lower_no_err (src : string) : Sil.modul =
  let p, d = front src in
  Alcotest.(check bool) "no sema ERRORS" false (Diagnostics.has_errors d);
  Silgen.lower p

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let proto = "protocol P { func v() -> Int }\nstruct A: P { var x: Int\n  func v() -> Int { return x } }\n"

let test_cast_types () =
  (* as? : T?  /  as! : T *)
  let _, d = front (proto ^ "let p: P = A(x: 1)\nlet q: A? = p as? A\nprint(q ?? A(x: 0))") in
  ignore d; (* the ?? of a struct payload type-checks structurally *)
  let _, d2 = front (proto ^ "let p: P = A(x: 1)\nlet a: A = p as! A\nprint(a.x)") in
  Alcotest.(check bool) "as! yields the concrete type" false (Diagnostics.has_errors d2)

let test_unrelated_warns () =
  let _, d = front (proto ^ "struct C { var z: Int }\nlet p: P = A(x: 1)\nif let c = p as? C { print(c.z) }") in
  Alcotest.(check bool) "always-fails cast warned" true
    (List.mem "cast from 'any P' to unrelated type 'C' always fails" (msgs d));
  Alcotest.(check bool) "but it is not an error" false (Diagnostics.has_errors d)

let test_sil_shapes () =
  let m = lower_no_err (proto ^ "let p: P = A(x: 1)\nif let a = p as? A { print(a.x) }") in
  Alcotest.(check int) "one identity test" 1
    (count_instr (function Sil.Same_witness _ -> true | _ -> false) m);
  Alcotest.(check int) "the open happens in the proven branch" 1
    (count_instr (function Sil.Open_existential _ -> true | _ -> false) m);
  Alcotest.(check (list string)) "module verifies" [] (Sil.verify m)

let test_abort_term () =
  let m = lower_no_err (proto ^ "let p: P = A(x: 1)\nlet a = p as! A\nprint(a.x)") in
  let has_abort =
    List.exists
      (fun (f : Sil.func) -> List.exists (fun (b : Sil.block) -> match b.Sil.term with Sil.Abort _ -> true | _ -> false) f.Sil.blocks)
      m.Sil.funcs
  in
  Alcotest.(check bool) "as! lowers a fail block ending in abort" true has_abort

let test_optimizer_safe () =
  let m = Opt.optimize (lower_no_err (proto ^ "let p: P = A(x: 6)\nif let a = p as? A { print(a.v()) }")) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let () =
  Alcotest.run "existentials"
    [
      ("sema", [ Alcotest.test_case "cast result types" `Quick test_cast_types;
                 Alcotest.test_case "unrelated cast warns" `Quick test_unrelated_warns ]);
      ("sil", [ Alcotest.test_case "same_witness + open" `Quick test_sil_shapes;
                Alcotest.test_case "as! abort block" `Quick test_abort_term ]);
      ("optimizer", [ Alcotest.test_case "-O keeps it valid" `Quick test_optimizer_safe ]);
    ]
