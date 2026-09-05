(* Alcotest unit tests for concept-34: the register-allocation ladder. *)
let vreg_func (src : string) : Arm64.func =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  let funcs, _ = Isel.select (Silgen.lower p) in
  (* the function with the most instructions (the interesting one) *)
  List.fold_left (fun a b -> if List.length b.Arm64.instrs > List.length a.Arm64.instrs then b else a)
    (List.hd funcs) (List.tl funcs)

(* a register-pressured straight-line program: several simultaneously-live temporaries *)
let pressured = "let a=1\nlet b=2\nlet c=3\nlet d=4\nlet e=5\nprint(a+b+c+d+e)\nprint(a*b+c*d)"
let loopy = "var s=0\nfor i in 0..<10 { s = s + i*i }\nprint(s)"

(* The eviction rule only fires when more values are live at once than the pool has registers, and
   raw (-Onone) SIL keeps variables in memory — so a Swift program of this subset rarely gets
   there. We hand-build the instruction stream instead, exactly as concept 27 hand-builds illegal
   SIL: define n virtual registers, then use them all, so all n are live across the middle. *)
let crowded n =
  Array.of_list
    (List.init n (fun i -> Arm64.Mov (Arm64.Virt i, Arm64.Imm i))
    @ List.init n (fun i -> Arm64.Str (Arm64.Virt i, Arm64.SP, 8 * i))
    @ [ Arm64.Ret ])

let instrs s = Array.of_list (vreg_func s).Arm64.instrs

let count_reg assign pred =
  Hashtbl.fold (fun _ l acc -> if pred l then acc + 1 else acc) assign 0

(* SOUNDNESS: two vregs whose live intervals OVERLAP must not get the same physical register *)
let sound assign instrs =
  let ivs = Regalloc.intervals instrs (Regalloc.liveness instrs) in
  let overlap (s1, e1) (s2, e2) = s1 <= e2 && s2 <= e1 in
  let ok = ref true in
  List.iter
    (fun (v1, i1) ->
      List.iter
        (fun (v2, i2) ->
          if v1 < v2 && overlap i1 i2 then
            match (Hashtbl.find_opt assign v1, Hashtbl.find_opt assign v2) with
            | Some (Regalloc.Reg r1), Some (Regalloc.Reg r2) -> if r1 = r2 then ok := false
            | _ -> ())
        ivs)
    ivs;
  !ok

let test_stack_spills_all () =
  let assign = Regalloc.stack_alloc (instrs pressured) in
  Alcotest.(check int) "stack: zero vregs in registers" 0 (count_reg assign (function Regalloc.Reg _ -> true | _ -> false))

let test_linscan_uses_registers () =
  let ins = instrs pressured in
  let assign = Regalloc.linscan ins in
  Alcotest.(check bool) "linscan keeps some values in registers" true
    (count_reg assign (function Regalloc.Reg _ -> true | _ -> false) > 0);
  Alcotest.(check bool) "linscan is sound (no overlap shares a register)" true (sound assign ins)

let test_graphcolor_uses_registers () =
  let ins = instrs pressured in
  let assign = Regalloc.graphcolor ins in
  Alcotest.(check bool) "graphcolor keeps some values in registers" true
    (count_reg assign (function Regalloc.Reg _ -> true | _ -> false) > 0);
  Alcotest.(check bool) "graphcolor is sound (proper colouring)" true (sound assign ins)

let test_sound_on_loop () =
  let ins = instrs loopy in
  Alcotest.(check bool) "linscan sound on a loop" true (sound (Regalloc.linscan ins) ins);
  Alcotest.(check bool) "graphcolor sound on a loop" true (sound (Regalloc.graphcolor ins) ins)

(* after allocation, NO virtual register may remain (the printer would reject one) *)
let no_virt (f : Arm64.func) =
  List.for_all
    (fun i -> let r, w = Arm64.reads_writes i in not (List.exists Arm64.is_virt (r @ w)))
    f.Arm64.instrs

let test_run_is_physical () =
  List.iter
    (fun strat ->
      Alcotest.(check bool) "no virtual registers after allocation" true
        (no_virt (Regalloc.run strat (vreg_func pressured))))
    [ Regalloc.Stack; Regalloc.Linscan; Regalloc.Graphcolor ]

let test_fewer_spills_than_stack () =
  let ins = instrs loopy in
  let spills assign = count_reg assign (function Regalloc.Spill -> true | _ -> false) in
  Alcotest.(check bool) "graphcolor spills fewer than stack" true
    (spills (Regalloc.graphcolor ins) < spills (Regalloc.stack_alloc ins))

(* under real pressure the pool runs out and SOME value must go back to its slot — an allocator
   that never spills is either unsound or has an infinite pool *)
let test_linscan_spills_under_pressure () =
  let ins = crowded 14 in
  let assign = Regalloc.linscan ins in
  Alcotest.(check int) "14 live, 9 registers: 5 spilled" 5
    (count_reg assign (function Regalloc.Spill -> true | _ -> false));
  Alcotest.(check bool) "and the 9 kept are still sound" true (sound assign ins)

let test_graphcolor_spills_under_pressure () =
  let ins = crowded 14 in
  let assign = Regalloc.graphcolor ins in
  Alcotest.(check int) "14 mutually adjacent, 9 colours" 5
    (count_reg assign (function Regalloc.Spill -> true | _ -> false));
  Alcotest.(check bool) "and is still a proper colouring" true (sound assign ins)

(* the pool is the CALLEE-SAVED registers x19..x27 and nothing else: a value in one of them
   survives a `bl` with no save/restore at the call site *)
let allocated_regs assign =
  Hashtbl.fold (fun _ l acc -> match l with Regalloc.Reg r -> r :: acc | _ -> acc) assign []

let test_pool_is_callee_saved () =
  List.iter
    (fun alloc ->
      Alcotest.(check bool) "every allocated register is in x19..x27" true
        (List.for_all (fun r -> List.mem r Regalloc.pool) (allocated_regs (alloc (instrs pressured)))))
    [ Regalloc.linscan; Regalloc.graphcolor ]

(* PROOFREAD #8: `stp x29, x30, [sp, #frame-16]` overflowed stp's 7-bit scaled immediate once the
   frame grew. The record is pushed first now, so every stp/ldp uses offset 0 whatever the frame. *)
let wide = String.concat "\n" (List.init 40 (fun i -> Printf.sprintf "let z%d=%d" i i))
           ^ "\nprint(" ^ String.concat "+" (List.init 40 (fun i -> Printf.sprintf "z%d" i)) ^ ")"

let test_frame_record_at_zero () =
  let f = Regalloc.run Regalloc.Graphcolor (vreg_func wide) in
  Alcotest.(check bool) "no stp/ldp uses a nonzero offset" true
    (List.for_all
       (fun i -> match i with Arm64.Stp (_, _, _, o) | Arm64.Ldp (_, _, _, o) -> o = 0 | _ -> true)
       f.Arm64.instrs);
  Alcotest.(check bool) "the frame really is past stp's range" true (f.Arm64.nslots * 8 > 504)

let () =
  Alcotest.run "regalloc"
    [
      ( "given: the stack rung and the frame",
        [
          Alcotest.test_case "stack spills all" `Quick test_stack_spills_all;
          Alcotest.test_case "frame record at offset 0" `Quick test_frame_record_at_zero;
        ] );
      ( "linscan (34a)",
        [
          Alcotest.test_case "uses registers" `Quick test_linscan_uses_registers;
          Alcotest.test_case "spills under pressure" `Quick test_linscan_spills_under_pressure;
        ] );
      ( "graphcolor (34b)",
        [
          Alcotest.test_case "uses registers" `Quick test_graphcolor_uses_registers;
          Alcotest.test_case "spills under pressure" `Quick test_graphcolor_spills_under_pressure;
          Alcotest.test_case "fewer spills than stack" `Quick test_fewer_spills_than_stack;
        ] );
      ( "soundness (both rungs)",
        [
          Alcotest.test_case "sound on a loop" `Quick test_sound_on_loop;
          Alcotest.test_case "pool is callee-saved" `Quick test_pool_is_callee_saved;
          Alcotest.test_case "no virtual regs after run" `Quick test_run_is_physical;
        ] );
    ]
