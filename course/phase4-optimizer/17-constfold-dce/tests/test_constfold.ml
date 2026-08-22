(* Alcotest unit tests for concept-17: constant folding (Int/Bool/comparisons) + CFG simplification. *)

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

let test_fold_binop () =
  Alcotest.(check bool) "3 < 5 -> true" true (Opt.fold_binop Ast.Lt (Opt.CInt 3) (Opt.CInt 5) = Some (Opt.CBool true));
  Alcotest.(check bool) "7 == 7 -> true" true (Opt.fold_binop Ast.Eq (Opt.CInt 7) (Opt.CInt 7) = Some (Opt.CBool true));
  Alcotest.(check bool) "true && false -> false" true (Opt.fold_binop Ast.And (Opt.CBool true) (Opt.CBool false) = Some (Opt.CBool false));
  Alcotest.(check bool) "2 + 3 -> 5" true (Opt.fold_binop Ast.Add (Opt.CInt 2) (Opt.CInt 3) = Some (Opt.CInt 5));
  Alcotest.(check bool) "1 / 0 -> None (keep the trap)" true (Opt.fold_binop Ast.Div (Opt.CInt 1) (Opt.CInt 0) = None)

let test_const_fold () =
  let m = run [ ("cf", Opt.constant_fold) ] (lower "print(3 < 5)") in
  Alcotest.(check int) "comparison folded away" 0 (count_instr is_binop m);
  Alcotest.(check bool) "folded to the bool true" true (count_instr (has_bool true) m >= 1)

let test_simplify_cfg () =
  let m = lower "if 3 < 5 { print(1) } else { print(2) }" in
  let before = count_blocks m in
  let m' = run [ ("cf", Opt.constant_fold); ("scf", Opt.simplify_cfg) ] m in
  Alcotest.(check int) "the constant branch is gone" 0 (count_condbr m');
  Alcotest.(check bool) "the unreachable else block was deleted" true (count_blocks m' < before)

let test_preserves_valid () =
  let m = run [ ("m", Opt.mem2reg); ("cf", Opt.constant_fold); ("scf", Opt.simplify_cfg) ]
      (lower "var s = 0\nfor i in 0 ..< 3 { if i > 0 { s = s + i } }\nprint(s)")
  in
  Alcotest.(check (list string)) "SIL still verifies after the passes" [] (Sil.verify m)

let () =
  Alcotest.run "constfold"
    [
      ("fold", [ Alcotest.test_case "fold_binop on constants" `Quick test_fold_binop;
                Alcotest.test_case "constant_fold pass" `Quick test_const_fold ]);
      ("cfg", [ Alcotest.test_case "branch + dead-block elimination" `Quick test_simplify_cfg ]);
      ("safety", [ Alcotest.test_case "passes keep SIL valid" `Quick test_preserves_valid ]);
    ]
