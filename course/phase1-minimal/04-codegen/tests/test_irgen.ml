(* Alcotest unit tests for IRGen (concept 04).

   The headline correctness check for codegen is the *runtime* oracle (`make oracle`,
   compare stdout/exit vs swiftc). These unit tests are complementary: they pin the
   *shape* of the emitted LLVM IR — the preamble, the alloca/load/store slot model, and
   especially the opcode mapping (signed `sdiv`/`srem`, unary as `0 - x`) — so a wrong
   mapping is caught and localized here, not just at runtime.

   RED until you implement `irgen.ml : emit_llvm`; GREEN against `solution/irgen.ml`. *)

let emit (src : string) : string =
  let diags = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) diags) in
  Irgen.emit_llvm p

let contains haystack needle =
  let n = String.length haystack and m = String.length needle in
  let rec go i = i + m <= n && (String.sub haystack i m = needle || go (i + 1)) in
  m = 0 || go 0

let has src needle =
  Alcotest.(check bool) (Printf.sprintf "%S emits %S" src needle) true (contains (emit src) needle)

let lacks src needle =
  Alcotest.(check bool) (Printf.sprintf "%S must NOT emit %S" src needle) false (contains (emit src) needle)

let test_preamble () =
  has "print(1)" "declare i32 @printf(ptr, ...)";
  has "print(1)" "@.fmt";
  has "print(1)" "define i32 @main()";
  has "print(1)" "ret i32 0";
  has "print(7)" "call i32 (ptr, ...) @printf"

let test_opcodes () =
  has "print(1 + 2)" "add i64";
  has "print(3 - 1)" "sub i64";
  has "print(2 * 3)" "mul i64";
  has "print(9 / 3)" "sdiv i64";
  has "print(9 % 4)" "srem i64";
  (* unary minus is lowered as 0 - x *)
  has "print(-5)" "sub i64 0,"

let test_signedness () =
  (* the signed-vs-unsigned choice matters for parity — never the unsigned forms *)
  lacks "print(9 / 3)" "udiv";
  lacks "print(9 % 4)" "urem"

let test_slot_model () =
  has "let x = 5\nprint(x)" "alloca i64";
  has "let x = 5\nprint(x)" "store i64";
  has "let x = 5\nprint(x)" "load i64"

let () =
  Alcotest.run "irgen"
    [
      ("preamble", [ Alcotest.test_case "module preamble + main" `Quick test_preamble ]);
      ("opcodes", [ Alcotest.test_case "binop / unary opcode mapping" `Quick test_opcodes ]);
      ("signedness", [ Alcotest.test_case "signed div/rem, not unsigned" `Quick test_signedness ]);
      ("slots", [ Alcotest.test_case "alloca/store/load model" `Quick test_slot_model ]);
    ]
