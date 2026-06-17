(* Alcotest unit tests for concept-24: devirtualization + generic specialization. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  Silgen.lower p

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let is_witness = function Sil.Apply_witness _ -> true | _ -> false

let proto = "protocol P { func v() -> Int }\nstruct A: P { var x: Int\n  func v() -> Int { return x } }\n"

let test_devirt () =
  (* a dispatch on a locally-built existential folds to a direct call *)
  let m = lower (proto ^ "let s: P = A(x: 21)\nprint(s.v())") in
  let m = Opt.optimize m in
  Alcotest.(check int) "no witness dispatch survives" 0 (count_instr is_witness m);
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let test_specialize () =
  let m = lower (proto ^ "func dbl<T: P>(_ t: T) -> Int { return t.v() + t.v() }\nprint(dbl(A(x: 10)))") in
  let m = Opt.optimize m in
  Alcotest.(check bool) "the clone dbl$A exists" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "dbl$A") m.Sil.funcs);
  Alcotest.(check int) "no witness dispatch survives" 0 (count_instr is_witness m);
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let test_unprovable_kept () =
  (* a plain function over a runtime-chosen existential must KEEP its dynamic dispatch *)
  let m = lower (proto ^ "struct B: P { func v() -> Int { return 7 } }\nfunc h(_ e: P) -> Int { return e.v() }\nvar e: P = A(x: 1)\nif 1 < 2 { e = B() }\nprint(h(e))") in
  let m = Opt.optimize m in
  Alcotest.(check bool) "dynamic dispatch survives where unprovable" true (count_instr is_witness m >= 1);
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let test_not_specializing_nongeneric () =
  (* a NON-generic function taking `any P` must not be cloned *)
  let m = lower (proto ^ "func h(_ e: P) -> Int { return e.v() }\nprint(h(A(x: 2)))") in
  let m = Opt.optimize m in
  Alcotest.(check bool) "no h$A clone" true
    (not (List.exists (fun (f : Sil.func) -> f.Sil.fname = "h$A") m.Sil.funcs))

let () =
  Alcotest.run "spec"
    [
      ("devirt", [ Alcotest.test_case "known wrap -> direct call" `Quick test_devirt ]);
      ("specialize", [ Alcotest.test_case "clone per concrete type" `Quick test_specialize;
                       Alcotest.test_case "unprovable stays dynamic" `Quick test_unprovable_kept;
                       Alcotest.test_case "non-generic not cloned" `Quick test_not_specializing_nongeneric ]);
    ]
