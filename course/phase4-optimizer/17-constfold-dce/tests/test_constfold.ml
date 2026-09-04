(* Alcotest unit tests for concept-17: constant folding (Int/Bool/comparisons) + CFG
   simplification. Grouped by the two TODO(17) holes, so a half-filled pair says which is out. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Silgen.lower p

let run passes (m : Sil.modul) : Sil.modul =
  Opt.run_pipeline (List.map (fun (n, r) -> { Opt.name = n; run = r }) passes) m

let count_blocks (m : Sil.modul) : int =
  List.fold_left (fun a (f : Sil.func) -> a + List.length f.Sil.blocks) 0 m.Sil.funcs

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) -> List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let count_condbr (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) -> List.fold_left (fun acc (b : Sil.block) -> match b.Sil.term with Sil.Cond_br _ -> acc + 1 | _ -> acc) acc f.Sil.blocks)
    0 m.Sil.funcs

let is_binop = function Sil.Binop _ -> true | _ -> false
let has_bool b = function Sil.Bool_lit x -> x = b | _ -> false
let has_int n = function Sil.Int_lit x -> x = n | _ -> false

(* ---- hole (a): fold_binop ---- *)

let test_fold_arith () =
  let c op x y = Opt.fold_binop op (Opt.CInt x) (Opt.CInt y) in
  Alcotest.(check bool) "2 + 3 -> 5" true (c Ast.Add 2 3 = Some (Opt.CInt 5));
  Alcotest.(check bool) "2 - 3 -> -1" true (c Ast.Sub 2 3 = Some (Opt.CInt (-1)));
  Alcotest.(check bool) "2 * 3 -> 6" true (c Ast.Mul 2 3 = Some (Opt.CInt 6));
  Alcotest.(check bool) "-7 / 2 -> -3 (truncates)" true (c Ast.Div (-7) 2 = Some (Opt.CInt (-3)));
  Alcotest.(check bool) "-7 % 3 -> -1 (truncates)" true (c Ast.Mod (-7) 3 = Some (Opt.CInt (-1)))

let test_fold_compare () =
  let c op x y = Opt.fold_binop op (Opt.CInt x) (Opt.CInt y) in
  Alcotest.(check bool) "3 < 5" true (c Ast.Lt 3 5 = Some (Opt.CBool true));
  Alcotest.(check bool) "3 <= 3" true (c Ast.Le 3 3 = Some (Opt.CBool true));
  Alcotest.(check bool) "4 > 9 is false" true (c Ast.Gt 4 9 = Some (Opt.CBool false));
  Alcotest.(check bool) "4 >= 9 is false" true (c Ast.Ge 4 9 = Some (Opt.CBool false));
  Alcotest.(check bool) "7 == 7" true (c Ast.Eq 7 7 = Some (Opt.CBool true));
  Alcotest.(check bool) "7 != 7 is false" true (c Ast.Ne 7 7 = Some (Opt.CBool false))

let test_fold_bool () =
  (* SILGen never builds these — `&&` is a diamond — but a later pass can, so the arms exist *)
  let b op x y = Opt.fold_binop op (Opt.CBool x) (Opt.CBool y) in
  Alcotest.(check bool) "true && false -> false" true (b Ast.And true false = Some (Opt.CBool false));
  Alcotest.(check bool) "false || true -> true" true (b Ast.Or false true = Some (Opt.CBool true));
  Alcotest.(check bool) "true == true" true (b Ast.Eq true true = Some (Opt.CBool true))

let test_fold_no_zero_div () =
  (* no value exists to fold these to; the pass must not invent one. The two that DO fold are
     here so a fold_binop that answers None to everything fails this case too *)
  Alcotest.(check bool) "10 / 2 -> 5" true (Opt.fold_binop Ast.Div (Opt.CInt 10) (Opt.CInt 2) = Some (Opt.CInt 5));
  Alcotest.(check bool) "10 % 3 -> 1" true (Opt.fold_binop Ast.Mod (Opt.CInt 10) (Opt.CInt 3) = Some (Opt.CInt 1));
  Alcotest.(check bool) "1 / 0 -> None" true (Opt.fold_binop Ast.Div (Opt.CInt 1) (Opt.CInt 0) = None);
  Alcotest.(check bool) "1 % 0 -> None" true (Opt.fold_binop Ast.Mod (Opt.CInt 1) (Opt.CInt 0) = None)

let test_fold_type_mismatch () =
  (* an Int and a Bool never meet in well-typed SIL; folding one is a bug, not a nicety. The
     well-typed pair beside them keeps this case honest against a fold_binop that folds nothing *)
  Alcotest.(check bool) "1 + 2 -> 3" true (Opt.fold_binop Ast.Add (Opt.CInt 1) (Opt.CInt 2) = Some (Opt.CInt 3));
  Alcotest.(check bool) "Int + Bool -> None" true (Opt.fold_binop Ast.Add (Opt.CInt 1) (Opt.CBool true) = None);
  Alcotest.(check bool) "Bool < Bool -> None" true (Opt.fold_binop Ast.Lt (Opt.CBool true) (Opt.CBool false) = None)

let test_const_fold_pass () =
  let m = run [ ("cf", Opt.constant_fold) ] (lower "print(3 < 5)") in
  Alcotest.(check int) "comparison folded away" 0 (count_instr is_binop m);
  Alcotest.(check bool) "folded to the bool true" true (count_instr (has_bool true) m >= 1)

let test_fold_through_ssa () =
  (* THE payoff over concept 15: after mem2reg a `let` is a value, so the fold reaches through it *)
  let m = lower "let x = 6\nprint(x * x - (2 + 3))" in
  Alcotest.(check bool) "raw has binops" true (count_instr is_binop m >= 3);
  let m' = run [ ("m2r", Opt.mem2reg); ("cf", Opt.constant_fold) ] m in
  Alcotest.(check int) "everything folded" 0 (count_instr is_binop m');
  Alcotest.(check bool) "to the literal 31" true (count_instr (has_int 31) m' >= 1)

(* ---- hole (b): simplify_cfg ---- *)

let test_simplify_literal () =
  (* needs no folding: the condition is already a Bool literal *)
  let m = lower "if true { print(1) } else { print(2) }" in
  let before = count_blocks m in
  let m' = run [ ("scf", Opt.simplify_cfg) ] m in
  Alcotest.(check int) "the constant branch is gone" 0 (count_condbr m');
  Alcotest.(check bool) "the else block was deleted" true (count_blocks m' < before);
  Alcotest.(check int) "print(2) went with it" 0 (count_instr (has_int 2) m')

let test_simplify_false_side () =
  let m' = run [ ("cf", Opt.constant_fold); ("scf", Opt.simplify_cfg) ]
      (lower "if 1 == 2 { print(3) } else { print(4) }")
  in
  Alcotest.(check int) "no branch left" 0 (count_condbr m');
  Alcotest.(check int) "the then block went" 0 (count_instr (has_int 3) m');
  Alcotest.(check bool) "the else survived" true (count_instr (has_int 4) m' >= 1)

let test_simplify_keeps_args () =
  (* the taken edge's block arguments must come with it, or the merge reads nothing *)
  let m' = run [ ("m2r", Opt.mem2reg); ("scf", Opt.simplify_cfg) ]
      (lower "var x = 0\nif true { x = 11 } else { x = 22 }\nprint(x)")
  in
  Alcotest.(check (list string)) "SIL verifies (argument lists match)" [] (Sil.verify m');
  Alcotest.(check bool) "11 kept" true (count_instr (has_int 11) m' >= 1);
  Alcotest.(check int) "22 dropped with its block" 0 (count_instr (has_int 22) m')

let test_simplify_keeps_real_branch () =
  (* a loop test is not constant; deleting it would turn the loop into straight-line code. The
     constant `if true` in the body IS folded away, so exactly one branch must remain *)
  let m' = run [ ("m2r", Opt.mem2reg); ("cf", Opt.constant_fold); ("scf", Opt.simplify_cfg) ]
      (lower "var s = 0\nvar i = 0\nwhile i < 4 {\n  if true { s = s + i }\n  i = i + 1\n}\nprint(s)")
  in
  Alcotest.(check int) "the loop branch survives, the constant one does not" 1 (count_condbr m')

(* ---- safety ---- *)

let test_preserves_valid () =
  (* a positive claim first, so an identity pipeline cannot pass this case by doing nothing *)
  let folded = run [ ("cf", Opt.constant_fold) ] (lower "print(2 + 3)") in
  Alcotest.(check bool) "2 + 3 folded to 5" true (count_instr (has_int 5) folded >= 1);
  List.iter
    (fun src ->
      let m = run [ ("m", Opt.mem2reg); ("cf", Opt.constant_fold); ("scf", Opt.simplify_cfg) ] (lower src) in
      Alcotest.(check (list string)) "SIL still verifies after the passes" [] (Sil.verify m))
    [
      "var s = 0\nfor i in 0 ..< 3 { if i > 0 { s = s + i } }\nprint(s)";
      "if 2 > 1 { if 3 > 4 { print(7) } else { print(8) } } else { print(9) }";
      "func fib(_ n: Int) -> Int {\n  if n < 2 { return n }\n  return fib(n - 1) + fib(n - 2)\n}\nprint(fib(10))";
    ]

let () =
  Alcotest.run "constfold"
    [
      ( "fold_binop (hole a)",
        [
          Alcotest.test_case "Int arithmetic, truncating" `Quick test_fold_arith;
          Alcotest.test_case "the six comparisons" `Quick test_fold_compare;
          Alcotest.test_case "And/Or/Eq on Bools" `Quick test_fold_bool;
          Alcotest.test_case "div and mod by zero: None" `Quick test_fold_no_zero_div;
          Alcotest.test_case "mixed Int/Bool: None" `Quick test_fold_type_mismatch;
        ] );
      ( "constant_fold pass",
        [
          Alcotest.test_case "a comparison folds" `Quick test_const_fold_pass;
          Alcotest.test_case "folds through a promoted let" `Quick test_fold_through_ssa;
        ] );
      ( "simplify_cfg (hole b)",
        [
          Alcotest.test_case "literal true: branch+block go" `Quick test_simplify_literal;
          Alcotest.test_case "false side taken as readily" `Quick test_simplify_false_side;
          Alcotest.test_case "taken edge keeps its args" `Quick test_simplify_keeps_args;
          Alcotest.test_case "a real branch survives" `Quick test_simplify_keeps_real_branch;
        ] );
      ("safety", [ Alcotest.test_case "passes keep SIL valid" `Quick test_preserves_valid ]);
    ]
