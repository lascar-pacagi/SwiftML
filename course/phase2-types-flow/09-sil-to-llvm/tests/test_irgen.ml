(* Alcotest unit tests for concept-09 IRGen: the shape of the emitted LLVM IR, in-process, one
   group per TODO(09) hole. The runtime parity (build + run, and `oracle.t` vs swiftc) is the
   cram side; these read the text, so a case can count lines and look at where in the module
   something landed — which is how the entry-block alloca rule gets pinned. *)

let llvm (src : string) : string =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Irgen.emit_llvm (Silgen.lower p)

let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  m = 0 || go 0

let lines src = String.split_on_char '\n' (llvm src)
let has src needle = Alcotest.(check bool) (Printf.sprintf "%S has %S" src needle) true (contains (llvm src) needle)

let hasnt src needle =
  Alcotest.(check bool) (Printf.sprintf "%S lacks %S" src needle) false (contains (llvm src) needle)

let count src needle = List.length (List.filter (fun l -> contains l needle) (lines src))

(* the lines of @main's body, in order, from `define … @main` to its closing brace *)
let main_body src =
  let rec after = function
    | [] -> []
    | l :: rest -> if contains l "@main(" then rest else after rest
  in
  let rec upto = function [] -> [] | l :: rest -> if l = "}" then [] else l :: upto rest in
  upto (after (lines src))

(* ---- given: the module preamble and the alloca-hoisting rule ---- *)

let test_preamble () =
  has "print(1)" "declare i32 @printf(ptr, ...)";
  has "print(1)" "define i32 @main()";
  has "print(1)" "@.fmt_int = private unnamed_addr constant"

let test_allocas_in_entry () =
  (* a `let` inside a loop body must still alloca in the ENTRY block: an alloca in the loop
     would grow the stack every trip, and only entry-block allocas are promoted by mem2reg *)
  let src = "var s = 0\nfor i in 0 ..< 3 { let d = i * 2\n s = s + d }\nprint(s)" in
  let body = main_body src in
  let rec before_bb1 = function
    | [] -> []
    | l :: rest -> if l = "bb1:" then [] else l :: before_bb1 rest
  in
  let entry = before_bb1 body in
  Alcotest.(check int) "three allocas, all in bb0" 3
    (List.length (List.filter (fun l -> contains l "alloca") entry));
  Alcotest.(check int) "and none anywhere else" 3 (count src "alloca")

(* ---- TODO(09) gen_instr ---- *)

let test_memory () =
  has "let x = 1\nprint(x)" "= alloca i64";
  has "let x = 1\nprint(x)" "store i64 1, ptr";
  has "let x = 1\nprint(x)" "= load i64, ptr"

let test_literals_are_operands () =
  (* a literal is an operand, not an instruction: nothing in the module defines it *)
  hasnt "print(1)" "integer_literal";
  has "print(1)" "@printf(ptr @.fmt_int, i64 1)";
  has "print(true)" "select i1 1, ptr @.btrue, ptr @.bfalse"

let test_int_opcodes () =
  has "print(1 + 2)" "add i64";
  has "print(7 - 3)" "sub i64";
  has "print(2 * 3)" "mul i64";
  has "print(9 / 3)" "sdiv i64";
  has "print(9 % 4)" "srem i64";
  has "let n = 7\nprint(-n)" "sub i64 0,"

let test_compare_opcodes () =
  has "print(1 < 2)" "icmp slt i64";
  has "print(1 <= 2)" "icmp sle i64";
  has "print(2 > 1)" "icmp sgt i64";
  has "print(2 >= 1)" "icmp sge i64";
  has "print(1 == 1)" "icmp eq i64";
  has "print(1 != 2)" "icmp ne i64"

let test_double_opcodes () =
  (* the operand type picks the mnemonic: Double arithmetic is the f-prefixed family *)
  has "let a = 1.5\nlet b = a + 2.5\nprint(b > a)" "fadd double";
  has "let a = 1.5\nlet b = a * 2.5\nprint(b > a)" "fmul double";
  has "let a = 1.5\nprint(a < 2.5)" "fcmp olt double"

let test_calls () =
  let src = "func add(_ a: Int, _ b: Int) -> Int { return a + b }\nfunc shout(_ n: Int) { print(n) }\nshout(add(1, 2))" in
  has src "define i64 @add(i64 ";
  has src "define void @shout(i64 ";
  has src "= call i64 @add(i64 1, i64 2)";
  has src "call void @shout(i64 ";
  (* a function_ref is an operand too — it emits no line of its own *)
  Alcotest.(check int) "one call line per apply" 2 (count src "call void @shout" + count src "call i64 @add")

(* ---- TODO(09) gen_term ---- *)

let test_br () =
  (* the loop's entry edge and its back-edge are both plain branches to the header *)
  let src = "var n = 0\nwhile n < 3 { n = n + 1 }\nprint(n)" in
  has src "br label %bb1";
  Alcotest.(check int) "two edges into the header" 2 (count src "br label %bb1")

let test_cond_br () =
  has "let x = 1\nif x < 0 { print(0) } else { print(1) }" "br i1 ";
  has "let x = 1\nif x < 0 { print(0) } else { print(1) }" ", label %bb"

let test_ret_typed () =
  has "func id(_ x: Int) -> Int { return x }\nprint(id(1))" "  ret i64 ";
  has "func yes() -> Bool { return true }\nprint(yes())" "  ret i1 ";
  has "func shout(_ n: Int) { print(n) }\nshout(1)" "  ret void"

let test_main_returns_i32 () =
  (* @main is the C entry point: SIL returns $() but LLVM must return the exit code *)
  has "print(1)" "  ret i32 0";
  hasnt "print(1)" "define void @main"

let test_unreachable () =
  has "func pick(_ c: Bool) -> Int { if c { return 1 } else { return 2 } }\nprint(pick(true))" "  unreachable"

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
        ] );
      ( "hole: gen_term",
        [
          Alcotest.test_case "br label" `Quick test_br;
          Alcotest.test_case "cond_br is br i1" `Quick test_cond_br;
          Alcotest.test_case "ret takes the ret type" `Quick test_ret_typed;
          Alcotest.test_case "@main returns i32 0" `Quick test_main_returns_i32;
          Alcotest.test_case "unreachable survives" `Quick test_unreachable;
        ] );
    ]
