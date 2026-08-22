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

let () =
  Alcotest.run "regalloc"
    [
      ( "ladder",
        [
          Alcotest.test_case "stack spills all" `Quick test_stack_spills_all;
          Alcotest.test_case "linscan uses registers" `Quick test_linscan_uses_registers;
          Alcotest.test_case "graphcolor uses registers" `Quick test_graphcolor_uses_registers;
          Alcotest.test_case "fewer spills than stack" `Quick test_fewer_spills_than_stack;
        ] );
      ( "soundness",
        [
          Alcotest.test_case "sound on a loop" `Quick test_sound_on_loop;
          Alcotest.test_case "no virtual regs after run" `Quick test_run_is_physical;
        ] );
    ]
