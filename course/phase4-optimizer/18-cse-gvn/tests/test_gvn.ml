(* Alcotest unit tests for concept-18: GVN / common-subexpression elimination. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
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

let test_cse () =
  let m = lower "func f(_ x: Int) -> Int { return x * x + x * x }\nprint(f(5))" in
  let before = count is_mul m in
  let m' = run [ ("m2r", Opt.mem2reg); ("gvn", Opt.gvn) ] m in
  let after = count is_mul m' in
  Alcotest.(check bool) "raw has both multiplies" true (before >= 2);
  Alcotest.(check bool) "GVN eliminates the redundant one" true (after < before)

let test_dominance_cse () =
  (* (n*2) appears in the condition and both branches; GVN reuses it (the condition dominates both) *)
  let m = lower "func h(_ n: Int) -> Int {\n  if n * 2 > 10 { return n * 2 } else { return n * 2 + 1 }\n}\nprint(h(7))" in
  let m' = run [ ("m2r", Opt.mem2reg); ("gvn", Opt.gvn) ] m in
  Alcotest.(check (list string)) "valid after GVN" [] (Sil.verify m')

let test_impure_not_cse () =
  (* two calls to f(5) are NOT the same value (a call may have effects) — keep both *)
  let m = lower "func f(_ x: Int) -> Int { return x }\nprint(f(5) + f(5))" in
  let before = count is_apply m in
  let m' = run [ ("m2r", Opt.mem2reg); ("gvn", Opt.gvn) ] m in
  Alcotest.(check int) "calls are not CSE'd" before (count is_apply m')

let test_key_basics () =
  (* equal pure ops get equal keys; impure ops get none; same-shaped structs of DIFFERENT
     types must get different keys (a once-shipped bug merged `struct () $A` with `struct () $B`) *)
  let id v = v in
  Alcotest.(check bool) "same binop -> same key" true
    (Opt.value_key id Types.TInt (Sil.Binop (Ast.Add, 1, 2)) = Opt.value_key id Types.TInt (Sil.Binop (Ast.Add, 1, 2)));
  Alcotest.(check bool) "different operands -> different key" true
    (Opt.value_key id Types.TInt (Sil.Binop (Ast.Add, 1, 2)) <> Opt.value_key id Types.TInt (Sil.Binop (Ast.Add, 1, 3)));
  Alcotest.(check bool) "same fields, different struct type -> different key" true
    (Opt.value_key id (Types.TStruct "A") (Sil.Struct [ 1 ]) <> Opt.value_key id (Types.TStruct "B") (Sil.Struct [ 1 ]));
  Alcotest.(check bool) "a load is never keyed" true (Opt.value_key id Types.TInt (Sil.Load 0) = None)

let () =
  Alcotest.run "gvn"
    [
      ("cse", [ Alcotest.test_case "redundant subexpression removed" `Quick test_cse;
               Alcotest.test_case "CSE across a dominated join" `Quick test_dominance_cse ]);
      ("safety", [ Alcotest.test_case "impure ops not CSE'd" `Quick test_impure_not_cse ]);
      ("key", [ Alcotest.test_case "value keys" `Quick test_key_basics ]);
    ]
