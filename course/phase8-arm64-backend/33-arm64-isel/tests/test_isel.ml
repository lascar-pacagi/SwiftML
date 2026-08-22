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

let () =
  Alcotest.run "isel"
    [
      ( "frame",
        [
          Alcotest.test_case "prologue + ret" `Quick test_prologue;
          Alcotest.test_case "renders to asm text" `Quick test_printable;
        ] );
      ( "operations",
        [
          Alcotest.test_case "add + mul" `Quick test_arithmetic;
          Alcotest.test_case "mod = sdiv+msub" `Quick test_modulo;
          Alcotest.test_case "cmp + cset" `Quick test_comparison;
        ] );
      ( "calls & control flow",
        [
          Alcotest.test_case "direct bl" `Quick test_call;
          Alcotest.test_case "print -> printf" `Quick test_print_is_printf;
          Alcotest.test_case "branches" `Quick test_branches;
        ] );
    ]
