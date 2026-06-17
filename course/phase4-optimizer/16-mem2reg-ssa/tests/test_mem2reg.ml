(* Alcotest unit tests for concept-16 mem2reg: promote stack slots to SSA (block arguments). *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  Silgen.lower p

let m2r (m : Sil.modul) : Sil.modul = Opt.run_pipeline [ { Opt.name = "mem2reg"; run = Opt.mem2reg } ] m

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let count_block_args (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) -> List.fold_left (fun acc (b : Sil.block) -> acc + List.length b.Sil.args) acc f.Sil.blocks)
    0 m.Sil.funcs

let is_mem = function Sil.Alloc_stack _ | Sil.Load _ | Sil.Store _ -> true | _ -> false

let test_straightline () =
  (* a let used in the same block becomes a value — no stack traffic, no phis needed *)
  let m = lower "let x = 1\nlet y = 2\nprint(x + y)" in
  Alcotest.(check bool) "raw has memory ops" true (count_instr is_mem m > 0);
  let m' = m2r m in
  Alcotest.(check int) "no alloc/load/store after mem2reg" 0 (count_instr is_mem m');
  Alcotest.(check int) "no phis needed (straight-line)" 0 (count_block_args m')

let test_loop_phis () =
  (* a loop's induction + accumulator become block arguments (phis) at the header *)
  let m = lower "var s = 0\nfor i in 0 ..< 5 { s = s + i }\nprint(s)" in
  Alcotest.(check bool) "raw loop has memory ops" true (count_instr is_mem m >= 6);
  let m' = m2r m in
  Alcotest.(check int) "loop slots fully promoted" 0 (count_instr is_mem m');
  Alcotest.(check bool) "phis placed at the join (>= 2 block args)" true (count_block_args m' >= 2)

let test_if_phi () =
  (* a var assigned on both branches needs one phi at the merge *)
  let m = lower "var x = 0\nif 3 < 5 { x = 100 } else { x = 200 }\nprint(x)" in
  let m' = m2r m in
  Alcotest.(check int) "no memory ops left" 0 (count_instr is_mem m');
  Alcotest.(check bool) "a phi at the merge" true (count_block_args m' >= 1)

let test_struct_not_broken () =
  (* a struct accessed by field (struct_element_addr) is NOT promoted; mem2reg leaves it valid *)
  let m = lower "struct P { var x: Int; var y: Int }\nvar p = P(x: 1, y: 2)\np.x = 9\nprint(p.x)" in
  let m' = m2r m in
  Alcotest.(check (list string)) "still verifies after mem2reg" [] (Sil.verify m')

let () =
  Alcotest.run "mem2reg"
    [
      ("straightline", [ Alcotest.test_case "same-block let -> value" `Quick test_straightline ]);
      ("loops", [ Alcotest.test_case "loop carried vars -> phis" `Quick test_loop_phis ]);
      ("joins", [ Alcotest.test_case "if/else merge -> phi" `Quick test_if_phi ]);
      ("safety", [ Alcotest.test_case "non-promotable struct left valid" `Quick test_struct_not_broken ]);
    ]
