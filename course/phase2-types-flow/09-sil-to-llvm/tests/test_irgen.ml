(* Alcotest unit tests for concept-09 IRGen: the shape of the emitted LLVM IR, in-process, one
   group per TODO(09) hole. The runtime parity (build + run, and `oracle.t` vs swiftc) is the
   cram side; these read the text, so a case can count lines and look at where in the module
   something landed — which is how the entry-block alloca rule gets pinned. *)

let llvm_module ?(should_emit_terminator = fun _ -> true) sil_module =
  Irgen.emit_llvm ~should_emit_terminator sil_module

let llvm ?(should_emit_terminator = fun _ -> true) (src : string) : string =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  llvm_module ~should_emit_terminator (Silgen.lower p)

let instruction_llvm = llvm ~should_emit_terminator:(fun _ -> false)

let terminator_llvm should_emit_terminator = llvm ~should_emit_terminator

let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  m = 0 || go 0

let instruction_has src needle =
  Alcotest.(check bool)
    (Printf.sprintf "%S has %S" src needle)
    true (contains (instruction_llvm src) needle)

let instruction_hasnt src needle =
  Alcotest.(check bool)
    (Printf.sprintf "%S lacks %S" src needle)
    false (contains (instruction_llvm src) needle)

let instruction_count src needle =
  String.split_on_char '\n' (instruction_llvm src)
  |> List.filter (fun line -> contains line needle)
  |> List.length

(* the lines of @main's body, in order, from `define … @main` to its closing brace *)
let main_body_lines module_lines =
  let rec after = function
    | [] -> []
    | l :: rest -> if contains l "@main(" then rest else after rest
  in
  let rec upto = function [] -> [] | l :: rest -> if l = "}" then [] else l :: upto rest in
  upto (after module_lines)

(* ---- given: the module preamble and the alloca-hoisting rule ---- *)

let test_preamble () =
  instruction_has "" "declare i32 @printf(ptr, ...)";
  instruction_has "" "define i32 @main()";
  instruction_has "" "@.fmt_int = private unnamed_addr constant"

let test_allocas_in_entry () =
  (* Use only the given Alloc_stack case, so this given-code check passes before gen_instr. *)
  let value_types = Hashtbl.create 3 in
  List.iter (fun value -> Hashtbl.add value_types value Types.TInt) [ 0; 1; 2 ];
  let entry = { Sil.bid = 0; instrs = []; term = Sil.Return None } in
  let loop_body =
    {
      Sil.bid = 1;
      instrs =
        [ (2, Sil.Alloc_stack "third"); (1, Sil.Alloc_stack "second");
          (0, Sil.Alloc_stack "first") ];
      term = Sil.Return None;
    }
  in
  let func =
    {
      Sil.fname = "main";
      params = [];
      ret = Types.TVoid;
      blocks = [ loop_body; entry ];
      val_ty = value_types;
    }
  in
  let emitted =
    llvm_module ~should_emit_terminator:(fun _ -> false) { Sil.funcs = [ func ] }
  in
  let body = String.split_on_char '\n' emitted |> main_body_lines in
  let rec before_bb1 = function
    | [] -> []
    | l :: rest -> if l = "bb1:" then [] else l :: before_bb1 rest
  in
  let entry = before_bb1 body in
  Alcotest.(check int) "three allocas, all in bb0" 3
    (List.length (List.filter (fun l -> contains l "alloca") entry));
  Alcotest.(check int) "and none anywhere else" 3
    (List.length
       (List.filter (fun line -> contains line "alloca")
          (String.split_on_char '\n' emitted)))

(* ---- TODO(09) gen_instr ---- *)

let test_memory () =
  instruction_has "let x = 1\nx" "= alloca i64";
  instruction_has "let x = 1\nx" "store i64 1, ptr";
  instruction_has "let x = 1\nx" "= load i64, ptr"

let test_literals_are_operands () =
  (* a literal is an operand, not an instruction: nothing in the module defines it *)
  instruction_hasnt "let x = 1" "integer_literal";
  instruction_has "let x = 1" "store i64 1, ptr";
  instruction_has "let b = true" "store i1 1, ptr"

let test_int_opcodes () =
  instruction_has "1 + 2" "add i64";
  instruction_has "7 - 3" "sub i64";
  instruction_has "2 * 3" "mul i64";
  instruction_has "9 / 3" "sdiv i64";
  instruction_has "9 % 4" "srem i64";
  instruction_has "let n = 7\n-n" "sub i64 0,"

let test_compare_opcodes () =
  instruction_has "1 < 2" "icmp slt i64";
  instruction_has "1 <= 2" "icmp sle i64";
  instruction_has "2 > 1" "icmp sgt i64";
  instruction_has "2 >= 1" "icmp sge i64";
  instruction_has "1 == 1" "icmp eq i64";
  instruction_has "1 != 2" "icmp ne i64"

let test_double_opcodes () =
  (* the operand type picks the mnemonic: Double arithmetic is the f-prefixed family *)
  instruction_has "let a = 1.5\na + 2.5" "fadd double";
  instruction_has "let a = 1.5\na * 2.5" "fmul double";
  instruction_has "let a = 1.5\na < 2.5" "fcmp olt double"

let test_calls () =
  let src =
    "func add(_ a: Int, _ b: Int) -> Int { return a + b }\n\
     func sink(_ n: Int) {}\n\
     sink(add(1, 2))"
  in
  instruction_has src "define i64 @add(i64 ";
  instruction_has src "define void @sink(i64 ";
  instruction_has src "= call i64 @add(i64 1, i64 2)";
  instruction_has src "call void @sink(i64 ";
  instruction_hasnt src "= call void";
  (* a function_ref is an operand too — it emits no line of its own *)
  Alcotest.(check int) "one call line per apply" 2
    (instruction_count src "call void @sink" + instruction_count src "call i64 @add")

let test_print () =
  instruction_has "print(1)" "@printf(ptr @.fmt_int, i64 1)";
  instruction_has "print(true)" "select i1 1, ptr @.btrue, ptr @.bfalse";
  instruction_has "print(1.5)" "@printf(ptr @.fmt_dbl, double";
  instruction_has "print(\"hi\")" "@printf(ptr @.fmt_str, ptr @.str0)"

(* ---- TODO(09) gen_term ---- *)

let test_br () =
  (* the loop's entry edge and its back-edge are both plain branches to the header *)
  let src = "var n = 0\nwhile n < 3 { n = n + 1 }\nprint(n)" in
  let emitted = terminator_llvm (function Sil.Br _ -> true | _ -> false) src in
  Alcotest.(check bool) "has br label %bb1" true (contains emitted "br label %bb1");
  Alcotest.(check int) "two edges into the header" 2
    (String.split_on_char '\n' emitted
    |> List.filter (fun line -> contains line "br label %bb1")
    |> List.length)

let test_cond_br () =
  let src = "let x = 1\nif x < 0 { print(0) } else { print(1) }" in
  let emitted = terminator_llvm (function Sil.Cond_br _ -> true | _ -> false) src in
  Alcotest.(check bool) "has br i1" true (contains emitted "br i1 ");
  Alcotest.(check bool) "has typed block labels" true (contains emitted ", label %bb")

let test_ret_typed () =
  let emit_returns =
    terminator_llvm (function Sil.Return (Some _) -> true | _ -> false)
  in
  let has_return src expected =
    Alcotest.(check bool) expected true (contains (emit_returns src) expected)
  in
  has_return "func id(_ x: Int) -> Int { return x }\nprint(id(1))" "ret i64 ";
  has_return "func yes() -> Bool { return true }\nprint(yes())" "ret i1 "

let test_ret_void () =
  let emitted =
    terminator_llvm (function Sil.Return None -> true | _ -> false)
      "func shout(_ n: Int) { print(n) }\nshout(1)"
  in
  Alcotest.(check bool) "has ret void" true (contains emitted "ret void")

let test_main_returns_i32 () =
  (* @main is the C entry point: SIL returns $() but LLVM must return the exit code *)
  let emitted =
    terminator_llvm (function Sil.Return None -> true | _ -> false) "print(1)"
  in
  Alcotest.(check bool) "main has ret i32 0" true (contains emitted "ret i32 0");
  Alcotest.(check bool) "main is not void" false (contains emitted "define void @main")

let test_unreachable () =
  let src =
    "func pick(_ c: Bool) -> Int { if c { return 1 } else { return 2 } }\n\
     print(pick(true))"
  in
  let emitted =
    terminator_llvm (function Sil.Unreachable -> true | _ -> false) src
  in
  Alcotest.(check bool) "has unreachable" true (contains emitted "unreachable")

let () =
  Alcotest.run "irgen"
    [
      ( "given: preamble + alloca rule",
        [
          Alcotest.test_case "printf, formats, @main" `Quick test_preamble;
          Alcotest.test_case "allocas only in the entry" `Quick test_allocas_in_entry;
        ] );
      ( "hole: gen_instr",
        [
          Alcotest.test_case "alloca / load / store" `Quick test_memory;
          Alcotest.test_case "literals are operands" `Quick test_literals_are_operands;
          Alcotest.test_case "Int arithmetic mnemonics" `Quick test_int_opcodes;
          Alcotest.test_case "signed icmp predicates" `Quick test_compare_opcodes;
          Alcotest.test_case "Double picks the f-family" `Quick test_double_opcodes;
          Alcotest.test_case "func_ref + apply = call" `Quick test_calls;
          Alcotest.test_case "print dispatches by type" `Quick test_print;
        ] );
      ( "hole: gen_term",
        [
          Alcotest.test_case "br label" `Quick test_br;
          Alcotest.test_case "cond_br is br i1" `Quick test_cond_br;
          Alcotest.test_case "ret takes the ret type" `Quick test_ret_typed;
          Alcotest.test_case "bare return is ret void" `Quick test_ret_void;
          Alcotest.test_case "@main returns i32 0" `Quick test_main_returns_i32;
          Alcotest.test_case "unreachable survives" `Quick test_unreachable;
        ] );
    ]
