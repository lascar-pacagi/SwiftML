(* Alcotest unit tests for concept-35: AAPCS64 argument passing (stack args) + the frame. *)
let asm (src : string) : Arm64.func list =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
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

let () =
  Alcotest.run "abi"
    [
      ( "stack arguments",
        [
          Alcotest.test_case "args 9+ on the stack" `Quick test_stack_args_emitted;
          Alcotest.test_case "small calls register-only" `Quick test_small_calls_use_registers_only;
        ] );
      ( "frame",
        [
          Alcotest.test_case "large-frame-safe prologue" `Quick test_frame_safe_prologue;
          Alcotest.test_case "physical after allocation" `Quick test_no_virt_after_alloc;
        ] );
    ]
