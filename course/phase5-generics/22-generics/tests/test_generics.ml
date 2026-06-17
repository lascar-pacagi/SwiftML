(* Alcotest unit tests for concept-22: generic functions (inference + erased lowering). *)

let front (src : string) : Ast.program * Diagnostics.sink =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  (p, d)

let msgs (d : Diagnostics.sink) : string list =
  List.rev_map (fun (e : Diagnostics.t) -> e.Diagnostics.message) d.Diagnostics.diags

let lower (src : string) : Sil.modul =
  let p, d = front src in
  Alcotest.(check (list string)) "no sema errors" [] (msgs d);
  Silgen.lower p

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let proto = "protocol P { func v() -> Int }\nstruct A: P { var x: Int\n  func v() -> Int { return x } }\n"

let test_inference () =
  (* a valid generic call accepted; the result type is the CONCRETE binding *)
  let _, d = front (proto ^ "func id<T: P>(_ t: T) -> T { return t }\nlet a = id(A(x: 1))\nprint(a.x)") in
  Alcotest.(check (list string)) "T result usable concretely" [] (msgs d)

let test_conflict () =
  let _, d = front (proto ^ "struct B: P { func v() -> Int { return 2 } }\nfunc f<T: P>(_ a: T, _ b: T) -> Int { return 0 }\nprint(f(A(x: 1), B()))") in
  Alcotest.(check bool) "conflicting T rejected" true
    (List.mem "conflicting arguments to generic parameter 'T' ('A' vs. 'B')" (msgs d))

let test_constraint () =
  let _, d = front ("protocol P { func v() -> Int }\nstruct C { var y: Int }\nfunc f<T: P>(_ a: T) -> Int { return a.v() }\nprint(f(C(y: 1)))") in
  Alcotest.(check bool) "non-conformer rejected" true
    (List.mem "global function 'f' requires that 'C' conform to 'P'" (msgs d))

let test_unconstrained_rejected () =
  let _, d = front "func f<T>(_ a: T) -> T { return a }\nprint(1)" in
  Alcotest.(check bool) "v0 requires a constraint" true
    (List.exists (fun m -> m = "type parameter 'T' needs a protocol constraint in this subset (write '<T: SomeProtocol>')") (msgs d))

let test_erased_lowering () =
  let m = lower (proto ^ "func id<T: P>(_ t: T) -> T { return t }\nlet a = id(A(x: 1))\nprint(a.v())") in
  (* one copy of @id; the call wraps (init_existential) and opens (open_existential) *)
  Alcotest.(check int) "one wrap at the call" 1
    (count_instr (function Sil.Init_existential _ -> true | _ -> false) m);
  Alcotest.(check int) "one open of the T result" 1
    (count_instr (function Sil.Open_existential _ -> true | _ -> false) m);
  Alcotest.(check (list string)) "module verifies" [] (Sil.verify m)

let test_optimizer_safe () =
  let m = Opt.optimize (lower (proto ^ "func id<T: P>(_ t: T) -> T { return t }\nprint(id(A(x: 5)).v())")) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let () =
  Alcotest.run "generics"
    [
      ("inference", [ Alcotest.test_case "binds + substitutes" `Quick test_inference;
                      Alcotest.test_case "conflicting T" `Quick test_conflict;
                      Alcotest.test_case "constraint violation" `Quick test_constraint;
                      Alcotest.test_case "unconstrained rejected (v0)" `Quick test_unconstrained_rejected ]);
      ("lowering", [ Alcotest.test_case "erased once, wrap + open" `Quick test_erased_lowering ]);
      ("optimizer", [ Alcotest.test_case "-O keeps it valid" `Quick test_optimizer_safe ]);
    ]
