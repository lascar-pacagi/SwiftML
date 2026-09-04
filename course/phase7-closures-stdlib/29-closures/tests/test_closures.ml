(* Alcotest unit tests for concept-29: lifting, captures, the thick ABI, ownership, and the
   given store/type rules the closure work sits on. *)

let front (src : string) =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  (p, d)

let lower (src : string) : Sil.modul =
  let p, d = front src in
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  Silgen.lower p

let rejects (src : string) : bool = snd (front src) |> Diagnostics.has_errors

let instrs (m : Sil.modul) : Sil.instr list =
  List.concat_map
    (fun (f : Sil.func) -> List.concat_map (fun (b : Sil.block) -> List.map snd b.Sil.instrs) f.Sil.blocks)
    m.Sil.funcs

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.length (List.filter pred (instrs m))

let adder =
  "func makeAdder(_ n: Int) -> (Int) -> Int {\n  return { (x: Int) -> Int in x + n }\n}\nlet a = makeAdder(7)\nprint(a(1))"

(* ---- the lifting (TODO 29a) ---------------------------------------------------------- *)

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

let test_context_param () =
  (* parameter 0 of the lifted function IS the context, and the capture is read out of it *)
  let m = lower adder in
  let f = List.find (fun (f : Sil.func) -> f.Sil.fname = "makeAdder$clo0") m.Sil.funcs in
  Alcotest.(check bool) "ctx is parameter 0" true
    (match f.Sil.params with (_, Types.TClass "$ctx") :: _ -> true | _ -> false);
  Alcotest.(check int) "one capture_get" 1
    (List.length (List.filter (function Sil.Capture_get _ -> true | _ -> false) (instrs m)))

let test_two_literals () =
  (* two literals in one function lift to two numbered functions, each with its own context *)
  let m =
    lower
      "func pair(_ n: Int) -> Int {\n  let a = { (x: Int) -> Int in x + n }\n  let b = { (x: Int) -> Int in x * n }\n  return a(1) + b(2)\n}\nprint(pair(3))"
  in
  let names = List.map (fun (f : Sil.func) -> f.Sil.fname) m.Sil.funcs in
  Alcotest.(check bool) "clo0 and clo1" true
    (List.mem "pair$clo0" names && List.mem "pair$clo1" names);
  Alcotest.(check int) "two closures built" 2
    (count_instr (function Sil.Closure _ -> true | _ -> false) m)

let test_thin_to_thick () =
  (* a NAMED function as a value takes the thin->thick path — no lifting, a null context *)
  let m = lower "func dbl(_ x: Int) -> Int { return x * 2 }\nlet g = dbl\nprint(g(50))" in
  Alcotest.(check int) "one thin_to_thick" 1
    (count_instr (function Sil.Thin_to_thick _ -> true | _ -> false) m);
  Alcotest.(check int) "no closure built" 0
    (count_instr (function Sil.Closure _ -> true | _ -> false) m);
  Alcotest.(check int) "still an indirect call" 1
    (count_instr (function Sil.Apply_value _ -> true | _ -> false) m)

let test_ownership_clean () =
  (* function values are MANAGED: the ownership verifier must accept all generated SIL *)
  let m = lower adder in
  Alcotest.(check (list string)) "ownership-clean" [] (Sil.verify_ownership m)

let test_optimizer_safe () =
  let m = Opt.optimize (lower adder) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m);
  Alcotest.(check bool) "the lifted function survives -O" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "makeAdder$clo0") m.Sil.funcs)

(* ---- the capture discipline and the type rules (given) --------------------------------- *)

let test_capture_rules () =
  (* a mutation in a closure body can't even parse (single-expression bodies, v0) *)
  Alcotest.(check bool) "mutating body rejected" true
    (rejects "var n = 1\nlet f = { (x: Int) -> Int in n = x }");
  Alcotest.(check bool) "class capture rejected" true
    (rejects "class K { var v: Int\n  init() { v = 1 } }\nlet k = K()\nlet f = { () -> Int in k.v }")

let test_captured_fn_value () =
  (* CALLING a captured function value is a capture too — it used to compile, and miscompile *)
  Alcotest.(check bool) "captured fn call rejected" true
    (rejects
       "func mkAdd(_ n: Int) -> (Int) -> Int {\n  return { (x: Int) -> Int in x + n }\n}\nfunc compose(_ n: Int) -> (Int) -> Int {\n  let inner = mkAdd(n)\n  return { (x: Int) -> Int in inner(x) * 2 }\n}");
  Alcotest.(check bool) "a plain closure still accepted" false
    (rejects "func mkAdd(_ n: Int) -> (Int) -> Int {\n  return { (x: Int) -> Int in x + n }\n}\nlet f = mkAdd(2)\nprint(f(3))")

let test_one_diagnostic () =
  (* the body is checked ONCE — it used to be inferred and then checked, doubling every error *)
  let _, d = front "let f = { (x: Int) -> Int in x + y }" in
  Alcotest.(check int) "exactly one error" 1
    (List.length (List.filter (fun (m : Diagnostics.t) -> m.Diagnostics.severity = Diagnostics.Error) (Diagnostics.all d)))

let test_aggregate_rules () =
  Alcotest.(check bool) "== on structs rejected" true
    (rejects "struct P { var x: Int; var y: Int }\nlet a = P(x: 1, y: 2)\nlet b = P(x: 1, y: 2)\nprint(a == b)");
  Alcotest.(check bool) "print of a struct rejected" true
    (rejects "struct P { var x: Int; var y: Int }\nprint(P(x: 1, y: 2))");
  Alcotest.(check bool) "let field write rejected" true
    (rejects "struct P { let x: Int; var y: Int }\nvar p = P(x: 1, y: 2)\np.x = 9");
  Alcotest.(check bool) "var field write accepted" false
    (rejects "struct P { let x: Int; var y: Int }\nvar p = P(x: 1, y: 2)\np.y = 9\nprint(p.y)")

(* ---- the store lowerings the closure work sits on (given) ------------------------------ *)

let test_double_operand () =
  (* `d * 2` must generate the literal AT Double, or IRGen emits `fmul double %d, 2` *)
  let m = lower "let d: Double = 2.5\nlet e = d * 2\nprint(e > 4.0)" in
  Alcotest.(check int) "no Int literal survives" 0
    (count_instr (function Sil.Int_lit _ -> true | _ -> false) m)

let test_member_stores () =
  (* an optional field is wrapped, and `self.v = e` finds self among the BORROWS, not the slots *)
  let m = lower "struct S { var o: Int? }\nvar s = S(o: nil)\ns.o = 5\nprint(s.o ?? 0)" in
  Alcotest.(check bool) "the store is of a wrapped enum" true
    (List.exists (function Sil.Enum _ -> true | _ -> false) (instrs m));
  let m2 =
    lower
      "class C { var v: Int\n  init(_ x: Int) { v = x }\n  func bump() { self.v = v + 1 } }\nlet c = C(1)\nc.bump()\nprint(c.v)"
  in
  Alcotest.(check bool) "self.v = e lowers to a field store" true
    (List.exists (function Sil.Ref_element_addr _ -> true | _ -> false) (instrs m2))

let () =
  Alcotest.run "closures"
    [
      ( "lifting",
        [
          Alcotest.test_case "lift + layout + ABI shapes" `Quick test_lifting;
          Alcotest.test_case "context is parameter 0" `Quick test_context_param;
          Alcotest.test_case "two literals, two functions" `Quick test_two_literals;
          Alcotest.test_case "named fn goes thin to thick" `Quick test_thin_to_thick;
        ] );
      ("ownership", [ Alcotest.test_case "verifier accepts fn values" `Quick test_ownership_clean ]);
      ( "captures",
        [
          Alcotest.test_case "discipline enforced" `Quick test_capture_rules;
          Alcotest.test_case "calling a captured value" `Quick test_captured_fn_value;
          Alcotest.test_case "one error, not two" `Quick test_one_diagnostic;
        ] );
      ( "given rules",
        [
          Alcotest.test_case "aggregates: == and print" `Quick test_aggregate_rules;
          Alcotest.test_case "Int literal beside a Double" `Quick test_double_operand;
          Alcotest.test_case "optional field and self.v" `Quick test_member_stores;
        ] );
      ("optimizer", [ Alcotest.test_case "-O keeps closures alive" `Quick test_optimizer_safe ]);
    ]
