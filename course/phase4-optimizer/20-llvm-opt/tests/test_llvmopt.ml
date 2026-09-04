(* Alcotest unit tests for concept-20: the full -O pipeline + the alloca-placement rule.

   The alloca tests pin a real bug this concept's benchmark caught: IRGen used to emit `alloca`
   inside the block where the `alloc_stack` appeared — so a `let` in a loop body allocated fresh
   stack EVERY iteration (stack space only returns at function exit), and a 3M-iteration bench
   segfaulted. The fix hoists every alloca into the entry block, like clang does. *)

let emit (src : string) : string =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
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
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
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

(* ---- the TODO(20) hole itself: does -O actually reach clang as -O2? ---- *)

(* Compile [src] at the given level and return the exit status of running the binary. LLVM at -O2
   turns self tail-recursion into a loop; at -O0 sixty million frames would need gigabytes of
   stack, so the process dies whatever the ulimit. The status alone says whether the flag got
   through — a stubbed "-O0" fails this. *)
let build_and_run ~(opt : bool) (src : string) : int =
  let dir = Filename.get_temp_dir_name () in
  let base = Filename.concat dir (Printf.sprintf "t20_%b_%d" opt (Unix.getpid ())) in
  let sf = base ^ ".swift" in
  let oc = open_out sf in
  output_string oc src;
  close_out oc;
  Driver.compile_file ~out:base ~opt ~src_path:sf ~emit:Driver.Exe ();
  let st = Sys.command (Printf.sprintf "%s >/dev/null 2>&1" (Filename.quote base)) in
  List.iter (fun f -> try Sys.remove f with _ -> ()) [ sf; base ];
  st

let deep_tail_recursion =
  "func count(_ n: Int, _ acc: Int) -> Int {\n  if n == 0 { return acc }\n  return count(n - 1, acc + 1)\n}\nprint(count(60000000, 0))"

let test_o2_reaches_clang () =
  (* -Onone is expected to die on the stack, which is also the control: if THIS returns 0 the
     program is not deep enough and the -O2 claim below would be vacuous *)
  Alcotest.(check bool) "-Onone overflows the stack" true (build_and_run ~opt:false deep_tail_recursion <> 0);
  Alcotest.(check int) "-O runs it as a loop" 0 (build_and_run ~opt:true deep_tail_recursion)

let () =
  Alcotest.run "llvmopt"
    [
      ("alloca", [ Alcotest.test_case "loop let hoisted" `Quick test_alloca_in_loop_hoisted;
                  Alcotest.test_case "loop struct hoisted" `Quick test_alloca_struct_in_loop_hoisted ]);
      ("pipeline", [ Alcotest.test_case "full -O end to end" `Quick test_opt_pipeline_end_to_end ]);
      ("clang", [ Alcotest.test_case "-O reaches clang as -O2" `Slow test_o2_reaches_clang ]);
    ]
