(* Alcotest unit tests for concept-35: AAPCS64 argument passing (stack args) + the frame. *)
let asm (src : string) : Arm64.func list =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  fst (Isel.select (Silgen.lower p))

let all m = List.concat_map (fun (f : Arm64.func) -> f.Arm64.instrs) m
let count pred m = List.length (List.filter pred (all m))

(* a 10-arg function + a call to it *)
let prog10 = "func g(_ a:Int,_ b:Int,_ c:Int,_ d:Int,_ e:Int,_ f:Int,_ h:Int,_ i:Int,_ j:Int,_ k:Int)->Int{ return a+j+k }\nprint(g(1,2,3,4,5,6,7,8,9,10))"
let prog2 = "func add(_ a:Int,_ b:Int)->Int{return a+b}\nprint(add(2,3))"

(* a store into the low outgoing area [sp,#0] or [sp,#8] = a stack-passed outgoing argument *)
let is_outgoing_store = function
  | Arm64.Str (Arm64.Virt _, Arm64.SP, off) when off = 0 || off = 8 -> true
  | _ -> false

(* a load from [x29, #16+] = an incoming stack parameter *)
let is_incoming_load = function
  | Arm64.Ldr (Arm64.Virt _, Arm64.X 29, off) when off >= 16 -> true
  | _ -> false

let test_stack_args_emitted () =
  let m = asm prog10 in
  Alcotest.(check bool) "outgoing stack-arg stores present" true (count is_outgoing_store m >= 2);
  Alcotest.(check bool) "incoming stack-param loads present" true (count is_incoming_load m >= 2)

let test_small_calls_use_registers_only () =
  (* a 2-arg call must NOT touch the stack-arg area *)
  let m = asm prog2 in
  Alcotest.(check int) "no incoming stack-param loads for <=8 params" 0 (count is_incoming_load m)

(* the frame is a CONTRACT: isel puts value v at [sp, #8*(outgoing+v)] and a spill of v must land
   on the same byte. A wide call grows `outgoing`, so a fixed base silently aliases an argument. *)
let prog14 = "func w(_ a:Int,_ b:Int,_ c:Int,_ d:Int,_ e:Int,_ f:Int,_ h:Int,_ i:Int,_ j:Int,_ k:Int,_ l:Int,_ m:Int,_ n:Int,_ o:Int)->Int{return a+n+o}\nvar t=0\nfor q in 0..<3 { t = t + w(q,1,2,3,4,5,6,7,8,9,10,11,12,13) }\nprint(t)"

let main_of m = List.hd (List.filter (fun (f : Arm64.func) -> f.Arm64.name = "main") m)

let test_spill_home_clears_outgoing () =
  let f = main_of (asm prog14) in
  Alcotest.(check int) "14 args = 6 outgoing words" 6 f.Arm64.outgoing;
  let g = Regalloc.run Regalloc.Stack f in
  let lo = 8 * f.Arm64.outgoing in
  (* every sp-relative spill the rewrite added is at or above the outgoing area; the only stores
     below it are the outgoing arguments themselves, which isel emitted *)
  let spill_below =
    List.exists
      (function
        | Arm64.Ldr (_, Arm64.SP, o) -> o < lo && o >= 16
        | _ -> false)
      g.Arm64.instrs
  in
  Alcotest.(check bool) "no reload from the outgoing area" false spill_below

let test_frame_safe_prologue () =
  (* the finalized function pushes fp/lr at offset 0 (large-frame-safe), never at frame-16 *)
  let f = Regalloc.run Regalloc.Graphcolor (List.hd (List.filter (fun (f : Arm64.func) -> f.Arm64.name = "g") (asm prog10))) in
  let stp0 = List.exists (function Arm64.Stp (Arm64.X 29, Arm64.X 30, Arm64.SP, 0) -> true | _ -> false) f.Arm64.instrs in
  Alcotest.(check bool) "fp/lr pushed at [sp, #0]" true stp0;
  (* x29 is set to the incoming sp for stack-arg access *)
  let setsfp = List.exists (function Arm64.Mov (Arm64.X 29, Arm64.R Arm64.SP) -> true | _ -> false) f.Arm64.instrs in
  Alcotest.(check bool) "x29 = incoming sp" true setsfp

let test_no_virt_after_alloc () =
  List.iter
    (fun f ->
      let g = Regalloc.run Regalloc.Graphcolor f in
      Alcotest.(check bool) ("physical after alloc: " ^ f.Arm64.name) true
        (List.for_all (fun i -> let r, w = Arm64.reads_writes i in not (List.exists Arm64.is_virt (r @ w))) g.Arm64.instrs))
    (asm prog10)

(* a locals area past `sub`'s 12-bit immediate is carved in steps; `as` rejects a bigger one *)
let wide_main =
  String.concat "\n" (List.init 200 (fun i -> Printf.sprintf "let z%d=%d" i i))
  ^ "\nprint(" ^ String.concat "+" (List.init 200 (fun i -> Printf.sprintf "z%d" i)) ^ ")"

let test_big_frame_immediates () =
  let f = Regalloc.run Regalloc.Graphcolor (main_of (asm wide_main)) in
  Alcotest.(check bool) "the frame really is past 4095 bytes" true (f.Arm64.nslots * 8 > 4095);
  let bad =
    List.exists
      (function
        | Arm64.Sub (Arm64.SP, Arm64.SP, Arm64.Imm n) | Arm64.Add (Arm64.SP, Arm64.SP, Arm64.Imm n) -> n > 4095
        | Arm64.Stp (_, _, _, o) | Arm64.Ldp (_, _, _, o) -> o <> 0
        | _ -> false)
      f.Arm64.instrs
  in
  Alcotest.(check bool) "every sp adjustment and pair offset is encodable" false bad

let () =
  Alcotest.run "abi"
    [
      ( "call site (35a)",
        [
          Alcotest.test_case "args 9+ on the stack" `Quick test_stack_args_emitted;
          Alcotest.test_case "small calls register-only" `Quick test_small_calls_use_registers_only;
        ] );
      ( "given: the frame contract",
        [
          Alcotest.test_case "spill home clears outgoing" `Quick test_spill_home_clears_outgoing;
          Alcotest.test_case "large-frame-safe prologue" `Quick test_frame_safe_prologue;
          Alcotest.test_case "big frame immediates fit" `Quick test_big_frame_immediates;
          Alcotest.test_case "physical after allocation" `Quick test_no_virt_after_alloc;
        ] );
    ]
