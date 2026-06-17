(* Alcotest unit tests for concept-29: lifting, captures, the thick ABI, ownership. *)

let front (src : string) =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  (p, d)

let lower (src : string) : Sil.modul =
  let p, d = front src in
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  Silgen.lower p

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let adder = "func makeAdder(_ n: Int) -> (Int) -> Int {\n  return { (x: Int) -> Int in x + n }\n}\nlet a = makeAdder(7)\nprint(a(1))"

let test_lifting () =
  let m = lower adder in
  Alcotest.(check bool) "the lifted function exists" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "makeAdder$clo0") m.Sil.funcs);
  Alcotest.(check bool) "its layout records the capture" true
    (match List.assoc_opt "makeAdder$clo0" m.Sil.closures with
    | Some [ ("n", Types.TInt) ] -> true
    | _ -> false);
  Alcotest.(check int) "one closure construction" 1
    (count_instr (function Sil.Closure _ -> true | _ -> false) m);
  Alcotest.(check int) "one indirect call" 1
    (count_instr (function Sil.Apply_value _ -> true | _ -> false) m)

let test_ownership_clean () =
  (* function values are MANAGED: the ownership verifier must accept all generated SIL *)
  let m = lower adder in
  Alcotest.(check (list string)) "ownership-clean" [] (Sil.verify_ownership m)

let test_capture_rules () =
  (* a mutation in a closure body can't even parse (single-expression bodies, v0) *)
  let _, d = front "var n = 1\nlet f = { (x: Int) -> Int in n = x }" in
  Alcotest.(check bool) "mutating body rejected (parse level)" true (Diagnostics.has_errors d);
  let _, d2 = front "class K { var v: Int\n  init() { v = 1 } }\nlet k = K()\nlet f = { () -> Int in k.v }" in
  Alcotest.(check bool) "class capture rejected" true (Diagnostics.has_errors d2)

let test_optimizer_safe () =
  let m = Opt.optimize (lower adder) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m);
  Alcotest.(check bool) "the lifted function survives -O" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "makeAdder$clo0") m.Sil.funcs)

let () =
  Alcotest.run "closures"
    [
      ("lifting", [ Alcotest.test_case "lift + layout + ABI shapes" `Quick test_lifting ]);
      ("ownership", [ Alcotest.test_case "verifier accepts fn values" `Quick test_ownership_clean ]);
      ("captures", [ Alcotest.test_case "discipline enforced" `Quick test_capture_rules ]);
      ("optimizer", [ Alcotest.test_case "-O keeps closures alive" `Quick test_optimizer_safe ]);
    ]
