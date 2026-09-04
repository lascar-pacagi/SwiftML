(* Alcotest unit tests for concept-18: GVN / common-subexpression elimination. Grouped by the two
   TODO(18) holes — the key, and the dominance-scoped walk that decides where a key is valid. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Silgen.lower p

let run passes (m : Sil.modul) : Sil.modul =
  Opt.run_pipeline (List.map (fun (n, r) -> { Opt.name = n; run = r }) passes) m

let count (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) -> List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let is_mul = function Sil.Binop (Ast.Mul, _, _) -> true | _ -> false
let is_apply = function Sil.Apply _ -> true | _ -> false
let is_extract = function Sil.Struct_extract _ -> true | _ -> false
let gvn_of src = run [ ("m2r", Opt.mem2reg); ("gvn", Opt.gvn) ] (lower src)

(* ---- hole (a): value_key — WHEN are two instructions the same value ---- *)

let id v = v

let test_key_equal () =
  Alcotest.(check bool) "same binop -> same key" true
    (Opt.value_key id Types.TInt (Sil.Binop (Ast.Add, 1, 2)) = Opt.value_key id Types.TInt (Sil.Binop (Ast.Add, 1, 2)));
  Alcotest.(check bool) "a key is produced at all" true
    (Opt.value_key id Types.TInt (Sil.Binop (Ast.Add, 1, 2)) <> None);
  Alcotest.(check bool) "literals are keyed" true (Opt.value_key id Types.TInt (Sil.Int_lit 7) <> None)

let test_key_different () =
  Alcotest.(check bool) "different operands -> different key" true
    (Opt.value_key id Types.TInt (Sil.Binop (Ast.Add, 1, 2)) <> Opt.value_key id Types.TInt (Sil.Binop (Ast.Add, 1, 3)));
  Alcotest.(check bool) "different operator -> different key" true
    (Opt.value_key id Types.TInt (Sil.Binop (Ast.Add, 1, 2)) <> Opt.value_key id Types.TInt (Sil.Binop (Ast.Sub, 1, 2)));
  Alcotest.(check bool) "different literal -> different key" true
    (Opt.value_key id Types.TInt (Sil.Int_lit 7) <> Opt.value_key id Types.TInt (Sil.Int_lit 8))

let test_key_type_matters () =
  (* the once-shipped bug: `struct () $A` and `struct () $B` had the same key and were merged,
     which produced ill-typed LLVM — the result type is part of what the instruction computes *)
  Alcotest.(check bool) "same fields, different struct type" true
    (Opt.value_key id (Types.TStruct "A") (Sil.Struct [ 1 ]) <> Opt.value_key id (Types.TStruct "B") (Sil.Struct [ 1 ]));
  Alcotest.(check bool) "same fields, same struct type" true
    (Opt.value_key id (Types.TStruct "A") (Sil.Struct [ 1 ]) = Opt.value_key id (Types.TStruct "A") (Sil.Struct [ 1 ]));
  Alcotest.(check bool) "same tag, different enum type" true
    (Opt.value_key id (Types.TEnum "E") (Sil.Enum (0, [])) <> Opt.value_key id (Types.TEnum "F") (Sil.Enum (0, [])))

let test_key_impure () =
  (* these must never be CSE'd, so they get no key at all — beside a pure one that does *)
  Alcotest.(check bool) "a binop is keyed" true (Opt.value_key id Types.TInt (Sil.Binop (Ast.Add, 1, 2)) <> None);
  Alcotest.(check bool) "load" true (Opt.value_key id Types.TInt (Sil.Load 0) = None);
  Alcotest.(check bool) "store" true (Opt.value_key id Types.TVoid (Sil.Store (1, 0)) = None);
  Alcotest.(check bool) "apply" true (Opt.value_key id Types.TInt (Sil.Apply (0, [ 1 ])) = None);
  Alcotest.(check bool) "print" true (Opt.value_key id Types.TVoid (Sil.Print 1) = None);
  Alcotest.(check bool) "alloc_stack" true (Opt.value_key id Types.TInt (Sil.Alloc_stack "x") = None);
  Alcotest.(check bool) "struct_element_addr" true (Opt.value_key id Types.TInt (Sil.Struct_element_addr (0, 0)) = None)

let test_key_canon () =
  (* operands go through `canon`, so two instructions on values already numbered equal match *)
  let canon v = if v = 3 then 1 else v in
  Alcotest.(check bool) "canonical operands compare equal" true
    (Opt.value_key canon Types.TInt (Sil.Binop (Ast.Add, 3, 2)) = Opt.value_key id Types.TInt (Sil.Binop (Ast.Add, 1, 2)))

(* ---- hole (b): the dominance-scoped walk — WHERE a key may be reused ---- *)

let test_cse () =
  let m = lower "func f(_ x: Int) -> Int { return x * x + x * x }\nprint(f(5))" in
  let before = count is_mul m in
  let after = count is_mul (gvn_of "func f(_ x: Int) -> Int { return x * x + x * x }\nprint(f(5))") in
  Alcotest.(check int) "raw has both multiplies" 2 before;
  Alcotest.(check int) "one multiply left" 1 after

let test_dominance_cse () =
  (* (n*2) appears in the condition and both branches; the condition dominates both, so one left *)
  let src = "func h(_ n: Int) -> Int {\n  if n * 2 > 10 { return n * 2 } else { return n * 2 + 1 }\n}\nprint(h(7))" in
  let before = count is_mul (lower src) in
  let m' = gvn_of src in
  Alcotest.(check int) "raw computes it three times" 3 before;
  Alcotest.(check int) "one left after GVN" 1 (count is_mul m');
  Alcotest.(check (list string)) "valid after GVN" [] (Sil.verify m')

let test_siblings_not_shared () =
  (* neither arm dominates the other: the walk must POP the then-arm's keys before the else arm,
     or the else arm reads a value never computed on its path *)
  let src = "func g(_ n: Int) -> Int {\n  var r = 0\n  if n > 0 { r = n * 3 } else { r = n * 3 + 1 }\n  return r\n}\nprint(g(4))" in
  let m' = gvn_of src in
  Alcotest.(check int) "both multiplies survive" 2 (count is_mul m');
  Alcotest.(check (list string)) "valid" [] (Sil.verify m')

let test_extract_cse () =
  let m' = gvn_of "struct P { var x: Int }\nfunc f(_ p: P) -> Int { return p.x + p.x }\nprint(f(P(x: 3)))" in
  Alcotest.(check int) "one struct_extract left" 1 (count is_extract m')

let test_impure_not_cse () =
  (* two calls to f(5) are NOT the same value (a call may have effects) — keep both, while the
     pure multiply beside them is merged *)
  let src = "func f(_ x: Int) -> Int { return x }\nfunc t(_ n: Int) -> Int { return f(n) + f(n) + n * n + n * n }\nprint(t(5))" in
  let before = count is_apply (lower src) in
  let m' = gvn_of src in
  Alcotest.(check int) "calls are not CSE'd" before (count is_apply m');
  Alcotest.(check int) "the multiply beside them is" 1 (count is_mul m')

let test_verifies_everywhere () =
  (* a positive claim first, so a gvn that does nothing cannot pass this case *)
  Alcotest.(check int) "the repeat in a loop is merged" 1
    (count is_mul (gvn_of "var s = 0\nfor i in 0 ..< 20 { s = s + i * i + i * i }\nprint(s)"));
  List.iter
    (fun src -> Alcotest.(check (list string)) "verifies" [] (Sil.verify (gvn_of src)))
    [
      "var s = 0\nfor i in 0 ..< 20 { s = s + i * i + i * i }\nprint(s)";
      "struct A { var x: Int }\nstruct B { var x: Int }\nfunc fb(_ b: B) -> Int { return b.x }\nprint(A(x: 1).x + fb(B(x: 1)))";
      "func fib(_ n: Int) -> Int {\n  if n < 2 { return n }\n  return fib(n - 1) + fib(n - 2)\n}\nprint(fib(10))";
    ]

let () =
  Alcotest.run "gvn"
    [
      ( "value_key (hole a)",
        [
          Alcotest.test_case "equal instructions, equal key" `Quick test_key_equal;
          Alcotest.test_case "operand and operator matter" `Quick test_key_different;
          Alcotest.test_case "result type is part of it" `Quick test_key_type_matters;
          Alcotest.test_case "impure and unique: no key" `Quick test_key_impure;
          Alcotest.test_case "operands run through canon" `Quick test_key_canon;
        ] );
      ( "scoped numbering (hole b)",
        [
          Alcotest.test_case "redundant subexpression goes" `Quick test_cse;
          Alcotest.test_case "reused across a dominated join" `Quick test_dominance_cse;
          Alcotest.test_case "siblings do not share" `Quick test_siblings_not_shared;
          Alcotest.test_case "struct_extract is CSE'd" `Quick test_extract_cse;
        ] );
      ( "safety",
        [
          Alcotest.test_case "calls kept, multiply merged" `Quick test_impure_not_cse;
          Alcotest.test_case "verifies on every shape" `Quick test_verifies_everywhere;
        ] );
    ]
