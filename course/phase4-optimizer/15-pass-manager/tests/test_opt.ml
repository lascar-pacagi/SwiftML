(* Alcotest unit tests for concept 15: the pass manager and constant folding, in-process.
   Each hole is exercised on its own — `run_pipeline` with the GIVEN dead_instr_elim pass,
   `constant_fold` called directly on a function — and then together through `Opt.optimize`.
   Passes mutate blocks in place, so every "before" count is taken BEFORE optimizing. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Silgen.lower p

let count_in (pred : Sil.instr -> bool) (f : Sil.func) : int =
  List.fold_left
    (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs))
    0 f.Sil.blocks

let count (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left (fun acc f -> acc + count_in pred f) 0 m.Sil.funcs

let total (m : Sil.modul) : int = count (fun _ -> true) m
let is_binop = function Sil.Binop _ -> true | _ -> false
let is_lit n = function Sil.Int_lit m -> m = n | _ -> false
let main_of (m : Sil.modul) : Sil.func = List.find (fun f -> f.Sil.fname = "main") m.Sil.funcs
let die = { Opt.name = "dead-instr-elim"; run = Opt.dead_instr_elim }

(* ---- run_pipeline: the manager, with the given DIE pass only ---- *)

let test_pipeline_runs_pass () =
  (* `a + 1` reads a slot, so folding could not touch it — only DIE (given) removes it *)
  let m = lower "let a = 1\na + 1\nprint(a)" in
  Alcotest.(check int) "raw: one dead binop" 1 (count is_binop m);
  let m' = Opt.run_pipeline [ die ] m in
  Alcotest.(check int) "after DIE: no binop" 0 (count is_binop m')

let test_pipeline_empty () =
  let m = lower "print(2 * 3 + 4)" in
  let before = total m in
  Alcotest.(check int) "empty pipeline is the identity" before (total (Opt.run_pipeline [] m));
  (* and a one-pass pipeline is NOT — otherwise "identity" would be satisfied by a manager that
     runs nothing at all *)
  let m2 = lower "let a = 1\na + 1\nprint(a)" in
  let before2 = total m2 in
  Alcotest.(check bool) "but one pass does change it" true
    (total (Opt.run_pipeline [ { Opt.name = "die"; run = Opt.dead_instr_elim } ] m2) < before2)

let test_pipeline_order_and_funcs () =
  (* a recording pass: which function it saw, under which pass name — in order *)
  let seen = ref [] in
  let spy name = { Opt.name; run = (fun f -> seen := (name, f.Sil.fname) :: !seen; f) } in
  let m = lower "func f(_ x: Int) -> Int {\n  return x\n}\nprint(f(1))" in
  ignore (Opt.run_pipeline [ spy "p1"; spy "p2" ] m);
  let trace = List.rev !seen in
  Alcotest.(check int) "2 passes x 2 functions" 4 (List.length trace);
  List.iter
    (fun (f : Sil.func) ->
      let mine = List.filter (fun (_, fn) -> fn = f.Sil.fname) trace in
      Alcotest.(check (list string)) ("p1 then p2 on " ^ f.Sil.fname) [ "p1"; "p2" ] (List.map fst mine))
    m.Sil.funcs

let test_pipeline_feeds_next () =
  (* the output of pass k is the input of pass k+1: a pass that empties main's blocks is seen by the next *)
  let wipe = { Opt.name = "wipe"; run = (fun f -> List.iter (fun (b : Sil.block) -> b.Sil.instrs <- []) f.Sil.blocks; f) } in
  let saw = ref None in
  let check = { Opt.name = "check"; run = (fun f -> saw := Some (count_in (fun _ -> true) f); f) } in
  ignore (Opt.run_pipeline [ wipe; check ] (lower "print(1)"));
  Alcotest.(check (option int)) "second pass saw the first's result" (Some 0) !saw

(* ---- constant_fold: the pass alone, on main ---- *)

let test_fold_literal () =
  let f = main_of (lower "print(1 + 2 * 3)") in
  Alcotest.(check int) "raw: two binops" 2 (count_in is_binop f);
  let f = Opt.constant_fold f in
  Alcotest.(check int) "folded: no binop" 0 (count_in is_binop f);
  Alcotest.(check bool) "the literal 7 appears" true (count_in (is_lit 7) f >= 1)

let test_fold_chain () =
  let f = Opt.constant_fold (main_of (lower "print(1 + 2 + 3 + 4)")) in
  Alcotest.(check int) "no binop" 0 (count_in is_binop f);
  Alcotest.(check bool) "folded to 10" true (count_in (is_lit 10) f >= 1)

let test_fold_truncates () =
  (* Swift's / and % truncate toward zero: (0-7)/2 = -3, (0-7)%3 = -1 *)
  let f = Opt.constant_fold (main_of (lower "print((0 - 7) / 2)\nprint((0 - 7) % 3)")) in
  Alcotest.(check int) "no binop" 0 (count_in is_binop f);
  Alcotest.(check bool) "-3 appears" true (count_in (is_lit (-3)) f >= 1);
  Alcotest.(check bool) "-1 appears" true (count_in (is_lit (-1)) f >= 1)

let test_fold_keeps_div_zero () =
  (* the /0 and %0 survive; the 10 / 2 beside them proves the pass ran *)
  let f = Opt.constant_fold (main_of (lower "print(10 / 0)\nprint(10 % 0)\nprint(10 / 2)")) in
  Alcotest.(check int) "the /0 and %0 binops survive" 2 (count_in is_binop f);
  Alcotest.(check bool) "10 / 2 folded to 5" true (count_in (is_lit 5) f >= 1)

let test_fold_keeps_comparison () =
  let f = Opt.constant_fold (main_of (lower "print(3 < 5)\nprint(3 + 5)")) in
  Alcotest.(check int) "comparison not folded (17)" 1 (count_in is_binop f);
  Alcotest.(check bool) "3 + 5 folded to 8" true (count_in (is_lit 8) f >= 1)

let test_fold_stops_at_loads () =
  let f = Opt.constant_fold (main_of (lower "let x = 1\nlet y = 2\nprint(x + y)\nprint(1 + 2)")) in
  Alcotest.(check int) "a binop of two loads stays" 1 (count_in is_binop f);
  Alcotest.(check bool) "1 + 2 folded to 3" true (count_in (is_lit 3) f >= 1)

(* ---- dead_instr_elim (given) ---- *)

let test_dce_keeps_effects () =
  (* run it THROUGH the manager, not by hand: the rule is what the pipeline must preserve *)
  let f = main_of (Opt.run_pipeline [ { Opt.name = "die"; run = Opt.dead_instr_elim } ] (lower "let a = 1\na + 1\nprint(a)")) in
  Alcotest.(check int) "dead binop gone" 0 (count_in is_binop f);
  Alcotest.(check int) "store kept" 1 (count_in (function Sil.Store _ -> true | _ -> false) f);
  Alcotest.(check int) "print kept" 1 (count_in (function Sil.Print _ | Sil.Apply _ -> true | _ -> false) f)

(* ---- the two together: Opt.optimize ---- *)

let test_optimize_shrinks () =
  let m = lower "print(1 + 2 * 3)" in
  let before = total m in
  let after = total (Opt.optimize m) in
  Alcotest.(check bool) "fewer instructions after -O" true (after < before);
  Alcotest.(check int) "no binop after -O" 0 (count is_binop (Opt.optimize (lower "print(1 + 2 * 3)")))

let () =
  Alcotest.run "opt"
    [
      ( "pipeline",
        [
          Alcotest.test_case "runs the given DIE pass" `Quick test_pipeline_runs_pass;
          Alcotest.test_case "empty pipeline is identity" `Quick test_pipeline_empty;
          Alcotest.test_case "in order, on every function" `Quick test_pipeline_order_and_funcs;
          Alcotest.test_case "each result feeds the next" `Quick test_pipeline_feeds_next;
        ] );
      ( "constant-fold",
        [
          Alcotest.test_case "1 + 2 * 3 folds to 7" `Quick test_fold_literal;
          Alcotest.test_case "chains fold to one literal" `Quick test_fold_chain;
          Alcotest.test_case "/ and % truncate like Swift" `Quick test_fold_truncates;
          Alcotest.test_case "/0 and %0 are not folded" `Quick test_fold_keeps_div_zero;
          Alcotest.test_case "comparisons are left alone" `Quick test_fold_keeps_comparison;
          Alcotest.test_case "stops at a load" `Quick test_fold_stops_at_loads;
        ] );
      ("dce", [ Alcotest.test_case "keeps store and print" `Quick test_dce_keeps_effects ]);
      ("optimize", [ Alcotest.test_case "-O shrinks and folds" `Quick test_optimize_shrinks ]);
    ]
