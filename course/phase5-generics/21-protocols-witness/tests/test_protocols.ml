(* Alcotest unit tests for concept-21: protocols, conformance, witness tables, dispatch. *)

let front (src : string) : Ast.program * Diagnostics.sink =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
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

let good = "protocol P { func v() -> Int }\nstruct A: P { var x: Int\n  func v() -> Int { return x } }\nstruct B: P { func v() -> Int { return 7 } }\nlet p: P = A(x: 1)\nprint(p.v())"

let test_conformance_ok () =
  let _, d = front good in
  Alcotest.(check (list string)) "conforming program accepted" [] (msgs d)

let test_conformance_missing () =
  let _, d = front "protocol P { func v() -> Int }\nstruct A: P { var x: Int }" in
  Alcotest.(check bool) "missing method rejected" true
    (List.mem "type 'A' does not conform to protocol 'P'" (msgs d))

let test_conformance_wrong_sig () =
  let _, d = front "protocol P { func v() -> Int }\nstruct A: P { func v() -> Bool { return true } }" in
  Alcotest.(check bool) "wrong signature rejected" true
    (List.mem "type 'A' does not conform to protocol 'P'" (msgs d))

let test_witness_tables () =
  let m = lower good in
  (* one table per conformance, impls in requirement order *)
  Alcotest.(check int) "two conformances -> two tables" 2 (List.length m.Sil.wtables);
  Alcotest.(check bool) "A's table points at A.v" true (List.mem ("P", "A", [ "A.v" ]) m.Sil.wtables);
  Alcotest.(check bool) "B's table points at B.v" true (List.mem ("P", "B", [ "B.v" ]) m.Sil.wtables);
  Alcotest.(check (list string)) "module verifies (tables reference real functions)" [] (Sil.verify m)

let test_dispatch_shapes () =
  let m = lower good in
  Alcotest.(check int) "one existential wrap" 1
    (count_instr (function Sil.Init_existential _ -> true | _ -> false) m);
  Alcotest.(check int) "one witness dispatch" 1
    (count_instr (function Sil.Apply_witness _ -> true | _ -> false) m);
  (* a method call on a CONCRETE receiver must stay a static Apply, not a table dispatch *)
  let m2 = lower "struct C { var r: Int\n  func a() -> Int { return r } }\nprint(C(r: 4).a())" in
  Alcotest.(check int) "static call: no witness dispatch" 0
    (count_instr (function Sil.Apply_witness _ -> true | _ -> false) m2)

let test_optimizer_safe () =
  (* the full -O pipeline must keep witness-table functions alive and the module valid *)
  let m = Opt.optimize (lower good) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m);
  Alcotest.(check bool) "witness impls survive -O (reachable via the table)" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "A.v") m.Sil.funcs)

let () =
  Alcotest.run "protocols"
    [
      ("conformance", [ Alcotest.test_case "accepts a conformer" `Quick test_conformance_ok;
                        Alcotest.test_case "missing method" `Quick test_conformance_missing;
                        Alcotest.test_case "wrong signature" `Quick test_conformance_wrong_sig ]);
      ("tables", [ Alcotest.test_case "one per conformance, slot order" `Quick test_witness_tables ]);
      ("dispatch", [ Alcotest.test_case "wrap + witness vs static" `Quick test_dispatch_shapes ]);
      ("optimizer", [ Alcotest.test_case "-O keeps tables valid" `Quick test_optimizer_safe ]);
    ]
