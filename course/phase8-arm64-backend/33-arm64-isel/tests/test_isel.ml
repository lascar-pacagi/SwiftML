(* Alcotest unit tests for concept-33: SIL -> ARM64 instruction selection. *)
let sil (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  Silgen.lower p

let asm (src : string) : Arm64.modul = Isel.select (sil src)

let all_instrs (m : Arm64.modul) : Arm64.instr list =
  List.concat_map (fun (f : Arm64.func) -> f.Arm64.instrs) m.Arm64.funcs

let count pred m = List.length (List.filter pred (all_instrs m))

let has_func m name = List.exists (fun (f : Arm64.func) -> f.Arm64.name = name) m.Arm64.funcs

let test_prologue () =
  (* every function has a stack-frame prologue: sub sp + stp x29,x30 *)
  let m = asm "print(1 + 2)" in
  Alcotest.(check bool) "main exists" true (has_func m "main");
  Alcotest.(check bool) "has stp prologue" true
    (count (function Arm64.Stp (Arm64.X 29, Arm64.X 30, _, _) -> true | _ -> false) m >= 1);
  Alcotest.(check bool) "has a ret" true (count (function Arm64.Ret -> true | _ -> false) m >= 1)

let test_arithmetic () =
  (* 2 + 3 * 4 lowers to one add and one mul *)
  let m = asm "print(2 + 3 * 4)" in
  Alcotest.(check bool) "has add" true (count (function Arm64.Add (_, _, _) -> true | _ -> false) m >= 1);
  Alcotest.(check bool) "has mul" true (count (function Arm64.Mul _ -> true | _ -> false) m >= 1)

let test_modulo () =
  (* a % b lowers to sdiv + msub (no native mod on arm64) *)
  let m = asm "print(17 % 5)" in
  Alcotest.(check bool) "has sdiv" true (count (function Arm64.Sdiv _ -> true | _ -> false) m >= 1);
  Alcotest.(check bool) "has msub" true (count (function Arm64.Msub _ -> true | _ -> false) m >= 1)

let test_comparison () =
  (* a comparison lowers to cmp + cset *)
  let m = asm "print(3 > 2)" in
  Alcotest.(check bool) "has cmp" true (count (function Arm64.Cmp _ -> true | _ -> false) m >= 1);
  Alcotest.(check bool) "has cset" true (count (function Arm64.Cset _ -> true | _ -> false) m >= 1)

let test_call () =
  (* a user function becomes its own asm func; the call site is a direct bl _name *)
  let m = asm "func g(_ a: Int) -> Int { return a + 1 }\nprint(g(41))" in
  Alcotest.(check bool) "g lowered" true (has_func m "g");
  Alcotest.(check bool) "direct bl _g" true (count (function Arm64.Bl "_g" -> true | _ -> false) m >= 1)

let test_print_is_printf () =
  let m = asm "print(42)" in
  Alcotest.(check bool) "calls _printf" true (count (function Arm64.Bl "_printf" -> true | _ -> false) m >= 1);
  Alcotest.(check bool) "a format cstring exists" true (m.Arm64.cstrings <> [])

let test_branches () =
  (* if/while produce conditional + unconditional branches *)
  let m = asm "var i = 0\nwhile i < 3 { i = i + 1 }\nprint(i)" in
  Alcotest.(check bool) "has b.cond" true (count (function Arm64.Bcond _ -> true | _ -> false) m >= 1);
  Alcotest.(check bool) "has b" true (count (function Arm64.B _ -> true | _ -> false) m >= 1)

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  go 0

let test_printable () =
  (* the printer renders without hitting a leftover virtual register *)
  let s = Arm64.string_of_module (asm "func f(_ n: Int) -> Int { return n * n }\nprint(f(7))") in
  Alcotest.(check bool) "asm has _main" true (contains s "_main:")


let count_in m name pred =
  let f = List.find (fun (f : Arm64.func) -> f.Arm64.name = name) m.Arm64.funcs in
  List.length (List.filter pred f.Arm64.instrs)

let test_big_constant () =
  (* 2^62 - 1 does not fit a mov: movz + three movk, one 16-bit chunk each *)
  let m = asm "print(4611686018427387903)" in
  Alcotest.(check int) "one movz" 1 (count (function Arm64.Movz _ -> true | _ -> false) m);
  Alcotest.(check int) "three movk" 3 (count (function Arm64.Movk _ -> true | _ -> false) m)

let test_bool_print () =
  (* print(Bool) selects "true"/"false" with csel and prints through %s *)
  let m = asm "print(3 > 2)" in
  Alcotest.(check bool) "has csel" true (count (function Arm64.Csel _ -> true | _ -> false) m >= 1);
  Alcotest.(check bool) "true cstring" true (List.mem_assoc "Ltrue" m.Arm64.cstrings);
  Alcotest.(check bool) "false cstring" true (List.mem_assoc "Lfalse" m.Arm64.cstrings)

let test_unsupported_is_comment () =
  (* an op outside v0 (a struct) lowers to a visible comment, never silent wrong code *)
  let m = asm "struct P { var x: Int }\nlet p = P(x: 1)\nprint(p.x)" in
  let n = count (function Arm64.Comment c -> contains c "UNSUPPORTED" | _ -> false) m in
  Alcotest.(check bool) "UNSUPPORTED comment emitted" true (n >= 1)

let test_main_returns_zero () =
  (* @main's `return` (no value) puts 0 in x0 — the process exit code *)
  let m = asm "print(1)" in
  Alcotest.(check int) "mov x0, #0 in main" 1
    (count_in m "main" (function Arm64.Mov (Arm64.X 0, Arm64.Imm 0) -> true | _ -> false))

let test_return_loads_x0 () =
  (* a `return v` loads v into x0 (from its slot) before the epilogue *)
  let m = asm "func one() -> Int { return 1 }\nprint(one())" in
  Alcotest.(check int) "ldr x0 in one" 1
    (count_in m "one" (function Arm64.Ldr (Arm64.X 0, Arm64.SP, _) -> true | _ -> false))

let test_trap_is_brk () =
  (* a trap terminator (force-unwrap of nil) is brk #1 *)
  let m = asm "let x: Int? = nil\nprint(x!)" in
  Alcotest.(check int) "one brk" 1 (count (function Arm64.Brk 1 -> true | _ -> false) m)

let test_frame_record_first () =
  (* the prologue pushes fp/lr at offset 0 BEFORE carving the locals, so a wide function (here
     ~130 values, a 1 KB frame) never asks stp for an offset beyond its 504-byte range *)
  let buf = Buffer.create 512 in
  Buffer.add_string buf "var s = 0\n";
  for i = 0 to 39 do Buffer.add_string buf (Printf.sprintf "s = s + %d\n" i) done;
  Buffer.add_string buf "print(s)";
  let m = asm (Buffer.contents buf) in
  let f = List.find (fun (f : Arm64.func) -> f.Arm64.name = "main") m.Arm64.funcs in
  (match f.Arm64.instrs with
  | Arm64.Sub (Arm64.SP, Arm64.SP, Arm64.Imm 16)
    :: Arm64.Stp (Arm64.X 29, Arm64.X 30, Arm64.SP, 0)
    :: Arm64.Mov (Arm64.X 29, Arm64.R Arm64.SP)
    :: Arm64.Sub (Arm64.SP, Arm64.SP, Arm64.Imm locals) :: _ ->
      Alcotest.(check bool) "locals area > 1 KB" true (locals > 1024)
  | _ -> Alcotest.fail "prologue is not sub 16 / stp [sp, #0] / mov x29, sp / sub locals");
  Alcotest.(check int) "every stp/ldp at offset 0" 0
    (count (function Arm64.Stp (_, _, _, o) | Arm64.Ldp (_, _, _, o) -> o <> 0 | _ -> false) m)

let () =
  Alcotest.run "isel"
    [
      ( "frame",
        [
          Alcotest.test_case "prologue + ret" `Quick test_prologue;
          Alcotest.test_case "frame record first; wide fn" `Quick test_frame_record_first;
          Alcotest.test_case "renders to asm text" `Quick test_printable;
        ] );
      ( "sel_instr (33a)",
        [
          Alcotest.test_case "add + mul" `Quick test_arithmetic;
          Alcotest.test_case "mod = sdiv+msub" `Quick test_modulo;
          Alcotest.test_case "cmp + cset" `Quick test_comparison;
          Alcotest.test_case "big constant = movz+movk" `Quick test_big_constant;
          Alcotest.test_case "direct bl" `Quick test_call;
          Alcotest.test_case "print -> printf" `Quick test_print_is_printf;
          Alcotest.test_case "print Bool -> csel + %s" `Quick test_bool_print;
          Alcotest.test_case "unsupported op = comment" `Quick test_unsupported_is_comment;
        ] );
      ( "sel_term (33b)",
        [
          Alcotest.test_case "branches" `Quick test_branches;
          Alcotest.test_case "main returns 0" `Quick test_main_returns_zero;
          Alcotest.test_case "return loads x0" `Quick test_return_loads_x0;
          Alcotest.test_case "trap = brk #1" `Quick test_trap_is_brk;
        ] );
    ]
