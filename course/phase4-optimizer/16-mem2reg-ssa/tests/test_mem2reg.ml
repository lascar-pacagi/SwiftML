(* Alcotest unit tests for concept-16 mem2reg: promote stack slots to SSA (block arguments).
   Grouped by the four rules of the renaming walk, so a half-filled hole says which rule is out. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
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

(* every branch argument list, so a rule that fills the wrong count is visible *)
let term_arg_counts (m : Sil.modul) : int list =
  List.concat_map
    (fun (f : Sil.func) ->
      List.concat_map
        (fun (b : Sil.block) ->
          match b.Sil.term with
          | Sil.Br (_, a) -> [ List.length a ]
          | Sil.Cond_br (_, (_, ta), (_, ea)) -> [ List.length ta; List.length ea ]
          | _ -> [])
        f.Sil.blocks)
    m.Sil.funcs

let is_mem = function Sil.Alloc_stack _ | Sil.Load _ | Sil.Store _ -> true | _ -> false

(* ---- rule 1/2: a store redefines, a load becomes, in straight-line code ---- *)

let test_straightline () =
  (* a let used in the same block becomes a value — no stack traffic, no phis needed *)
  let m = lower "let x = 1\nlet y = 2\nprint(x + y)" in
  Alcotest.(check bool) "raw has memory ops" true (count_instr is_mem m > 0);
  let m' = m2r m in
  Alcotest.(check int) "no alloc/load/store after mem2reg" 0 (count_instr is_mem m');
  Alcotest.(check int) "no phis needed (straight-line)" 0 (count_block_args m')

let test_reassign () =
  (* each store redefines the slot; the last one is what the load reads *)
  let m = lower "var x = 1\nx = x + 1\nx = x * 10\nprint(x)" in
  let before = count_instr is_mem m in
  let m' = m2r m in
  Alcotest.(check bool) "raw stored three times" true (before >= 4);
  Alcotest.(check int) "nothing left in memory" 0 (count_instr is_mem m');
  Alcotest.(check int) "still no phis" 0 (count_block_args m')

let test_param_slot () =
  (* a parameter is spilled at entry; promotion gives the body the parameter value itself *)
  let m = lower "func add1(_ n: Int) -> Int {\n  let m = n + 1\n  return m\n}\nprint(add1(4))" in
  let m' = m2r m in
  Alcotest.(check int) "parameter slot promoted" 0 (count_instr is_mem m')

(* ---- rule 3: a forward join takes an argument, each edge fills it ---- *)

let test_if_phi () =
  (* a var assigned on both branches needs one phi at the merge *)
  let m = lower "var x = 0\nif 3 < 5 { x = 100 } else { x = 200 }\nprint(x)" in
  let m' = m2r m in
  Alcotest.(check int) "no memory ops left" 0 (count_instr is_mem m');
  Alcotest.(check int) "exactly one phi at the merge" 1 (count_block_args m');
  Alcotest.(check bool) "some edge carries a value" true (List.exists (fun n -> n = 1) (term_arg_counts m'))

let test_dead_after_join () =
  (* pruned SSA at a plain join: x is dead after the merge, so no argument is placed *)
  let m = lower "var x = 0\nif 1 < 2 { x = 5 } else { x = 6 }\nprint(1)" in
  let m' = m2r m in
  Alcotest.(check int) "no phi for a dead variable" 0 (count_block_args m');
  Alcotest.(check (list int)) "every edge carries nothing" [ 0; 0; 0; 0 ] (term_arg_counts m')

(* ---- rule 4: a back edge fills an argument the walk has not computed yet ---- *)

let test_loop_phis () =
  (* a loop's induction + accumulator become block arguments (phis) at the header *)
  let m = lower "var s = 0\nfor i in 0 ..< 5 { s = s + i }\nprint(s)" in
  Alcotest.(check bool) "raw loop has memory ops" true (count_instr is_mem m >= 6);
  let m' = m2r m in
  Alcotest.(check int) "loop slots fully promoted" 0 (count_instr is_mem m');
  Alcotest.(check int) "two carried values at the header" 2 (count_block_args m');
  Alcotest.(check bool) "two edges carry both values" true
    (List.length (List.filter (fun n -> n = 2) (term_arg_counts m')) = 2)

let test_pruned_in_loop () =
  (* THE pruned-SSA case: `d` is dead on the entry edge, so the header must NOT ask for it *)
  let m = lower "var t = 0\nvar i = 0\nwhile i < 3 {\n  let d = i * i\n  t = t + d\n  i = i + 1\n}\nprint(t)" in
  let m' = m2r m in
  Alcotest.(check int) "header takes t and i, not d" 2 (count_block_args m');
  Alcotest.(check int) "loop is memory-free" 0 (count_instr is_mem m')

let test_nested_loop () =
  let m = lower "var t = 0\nfor i in 0 ..< 4 {\n  for j in 0 ..< 4 {\n    if j == i { continue }\n    t = t + i * j\n  }\n}\nprint(t)" in
  let m' = m2r m in
  Alcotest.(check int) "nested loops promoted" 0 (count_instr is_mem m');
  Alcotest.(check (list string)) "result verifies" [] (Sil.verify m')

(* ---- safety: what must survive untouched ---- *)

let test_struct_not_broken () =
  (* a struct accessed by field (struct_element_addr) is NOT promoted; mem2reg leaves it valid *)
  let m = lower "struct P { var x: Int; var y: Int }\nvar p = P(x: 1, y: 2)\np.x = 9\nprint(p.x)" in
  let m' = m2r m in
  Alcotest.(check bool) "field-addressed slot kept" true (count_instr is_mem m' > 0);
  Alcotest.(check (list string)) "still verifies after mem2reg" [] (Sil.verify m')

let test_verifies_everywhere () =
  (* the verifier is the real spec for the branch rule: a wrong-length argument list fails here *)
  List.iter
    (fun src ->
      let m' = m2r (lower src) in
      Alcotest.(check (list string)) "verifies" [] (Sil.verify m'))
    [
      "var s = 0\nfor i in 0 ..< 5 { s = s + i }\nprint(s)";
      "var x = 7\nif 3 < 5 { x = 100 }\nprint(x)";
      "var t = 0\nfor i in 0 ..< 8 {\n  if i == 2 { continue }\n  if i > 5 { break }\n  t = t + i\n}\nprint(t)";
      "func fib(_ n: Int) -> Int {\n  if n < 2 { return n }\n  return fib(n - 1) + fib(n - 2)\n}\nprint(fib(10))";
    ]

let () =
  Alcotest.run "mem2reg"
    [
      ( "straightline (store/load rules)",
        [
          Alcotest.test_case "same-block let -> value" `Quick test_straightline;
          Alcotest.test_case "reassignment; last store wins" `Quick test_reassign;
          Alcotest.test_case "parameter slot promoted" `Quick test_param_slot;
        ] );
      ( "joins (the branch rule)",
        [
          Alcotest.test_case "if/else merge -> one phi" `Quick test_if_phi;
          Alcotest.test_case "dead after join -> no phi" `Quick test_dead_after_join;
        ] );
      ( "loops (the back edge)",
        [
          Alcotest.test_case "loop carried vars -> phis" `Quick test_loop_phis;
          Alcotest.test_case "pruned: let in body, no phi" `Quick test_pruned_in_loop;
          Alcotest.test_case "nested loops promoted" `Quick test_nested_loop;
        ] );
      ( "safety",
        [
          Alcotest.test_case "non-promotable struct left valid" `Quick test_struct_not_broken;
          Alcotest.test_case "verifies on every shape" `Quick test_verifies_everywhere;
        ] );
    ]
