(* Alcotest unit tests for concept-20: the full -O pipeline + the alloca-placement rule.

   The alloca tests pin a real bug this concept's benchmark caught: IRGen used to emit `alloca`
   inside the block where the `alloc_stack` appeared — so a `let` in a loop body allocated fresh
   stack EVERY iteration (stack space only returns at function exit), and a 3M-iteration bench
   segfaulted. The fix hoists every alloca into the entry block, like clang does. *)

let emit (src : string) : string =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  Irgen.emit_llvm (Silgen.lower p)

(* every alloca must appear in the entry block (between "bb0:" and the next "bbN:" label) *)
let allocas_outside_entry (ir : string) : int =
  let lines = String.split_on_char '\n' ir in
  let in_entry = ref false and bad = ref 0 in
  List.iter
    (fun l ->
      if String.length l > 2 && String.sub l 0 2 = "bb" then in_entry := String.sub l 0 4 = "bb0:";
      let has_alloca =
        let rec find i = i + 6 <= String.length l && (String.sub l i 6 = "alloca" || find (i + 1)) in
        find 0
      in
      if has_alloca && not !in_entry then incr bad)
    lines;
  !bad

let test_alloca_in_loop_hoisted () =
  let ir = emit "var s = 0\nfor i in 0 ..< 5 { let p = i * 2; s = s + p }\nprint(s)" in
  Alcotest.(check int) "no alloca outside the entry block" 0 (allocas_outside_entry ir)

let test_alloca_struct_in_loop_hoisted () =
  let ir =
    emit
      "struct P { var x: Int; var y: Int }\nvar s = 0\nfor i in 0 ..< 5 { var p = P(x: i, y: i)\np.x = 9\ns = s + p.x }\nprint(s)"
  in
  Alcotest.(check int) "struct slot hoisted too" 0 (allocas_outside_entry ir)

let test_opt_pipeline_end_to_end () =
  (* the full -O SIL pipeline (inline + mem2reg + fold + cfg + gvn + dce) on a composite program *)
  let d = Diagnostics.create () in
  let src = "func sq(_ x: Int) -> Int { return x * x }\nvar s = 0\nfor i in 0 ..< 10 { s = s + sq(i) }\nprint(s)" in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  let m = Opt.optimize (Silgen.lower p) in
  Alcotest.(check (list string)) "optimized SIL verifies" [] (Sil.verify m);
  let mem =
    List.fold_left
      (fun acc (f : Sil.func) ->
        List.fold_left
          (fun acc (b : Sil.block) ->
            acc + List.length (List.filter (fun (_, i) -> match i with Sil.Alloc_stack _ | Sil.Load _ | Sil.Store _ -> true | _ -> false) b.Sil.instrs))
          acc f.Sil.blocks)
      0 m.Sil.funcs
  in
  Alcotest.(check int) "fully promoted to SSA (no memory traffic)" 0 mem

let () =
  Alcotest.run "llvmopt"
    [
      ("alloca", [ Alcotest.test_case "loop let hoisted" `Quick test_alloca_in_loop_hoisted;
                  Alcotest.test_case "loop struct hoisted" `Quick test_alloca_struct_in_loop_hoisted ]);
      ("pipeline", [ Alcotest.test_case "full -O end to end" `Quick test_opt_pipeline_end_to_end ]);
    ]
