(* Alcotest unit tests for concept-15: the pass manager + constant folding / DCE on SIL. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Silgen.lower p

let count (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let total (m : Sil.modul) : int = count (fun _ -> true) m
let is_binop = function Sil.Binop _ -> true | _ -> false
let is_lit n = function Sil.Int_lit m -> m = n | _ -> false

let test_constant_fold () =
  let m0 = lower "print(1 + 2 * 3)" in
  Alcotest.(check bool) "raw SIL has binops" true (count is_binop m0 >= 2);
  let m1 = Opt.optimize m0 in
  Alcotest.(check int) "optimized: no binops left" 0 (count is_binop m1);
  Alcotest.(check bool) "folded to the literal 7" true (count (is_lit 7) m1 >= 1)

let test_chained_fold () =
  (* (1 + 2) + 3 + 4 must fold all the way to 10 *)
  let m = Opt.optimize (lower "print(1 + 2 + 3 + 4)") in
  Alcotest.(check int) "no binops" 0 (count is_binop m);
  Alcotest.(check bool) "folded to 10" true (count (is_lit 10) m >= 1)

let test_dce () =
  let m0 = lower "print(1 + 2 * 3)" in
  let before = total m0 in (* capture BEFORE optimizing — the passes mutate in place *)
  let after = total (Opt.optimize m0) in
  (* DCE removes the now-dead literals and binops, shrinking the instruction count *)
  Alcotest.(check bool) "optimization removed instructions" true (after < before)

let test_pipeline () =
  (* the pass manager runs a given pass over each function *)
  let m = lower "print(2 * 3 + 4)" in
  let folded = Opt.run_pipeline [ { Opt.name = "cf"; run = Opt.constant_fold } ] m in
  Alcotest.(check int) "run_pipeline applied constant_fold" 0 (count is_binop folded);
  (* an empty pipeline is the identity (on a fresh module) *)
  let m2 = lower "print(2 * 3 + 4)" in
  Alcotest.(check int) "empty pipeline changes nothing" (total m2) (total (Opt.run_pipeline [] m2))

let () =
  Alcotest.run "opt"
    [
      ("constant-fold", [ Alcotest.test_case "literal arithmetic folds" `Quick test_constant_fold;
                          Alcotest.test_case "chains fold fully" `Quick test_chained_fold ]);
      ("dce", [ Alcotest.test_case "dead instructions removed" `Quick test_dce ]);
      ("pipeline", [ Alcotest.test_case "the pass manager runs passes" `Quick test_pipeline ]);
    ]
