(* Alcotest unit tests for concept-09 IRGen: the shape of the emitted LLVM IR. The runtime
   parity (build + run vs swiftc) is the cram test; these pin the IR. *)

let llvm (src : string) : string =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  Irgen.emit_llvm (Silgen.lower p)

let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  m = 0 || go 0

let has src needle = Alcotest.(check bool) (Printf.sprintf "%S has %S" src needle) true (contains (llvm src) needle)

let test_preamble () =
  has "print(1)" "declare i32 @printf(ptr, ...)";
  has "print(1)" "define i32 @main()";
  has "print(1)" "call i32 (ptr, ...) @printf(ptr @.fmt_int"

let test_memory () =
  has "let x = 1\nprint(x)" "= alloca i64";
  has "let x = 1\nprint(x)" "store i64";
  has "let x = 1\nprint(x)" "= load i64, ptr"

let test_opcodes () =
  has "print(1 + 2)" "add i64";
  has "print(7 - 3)" "sub i64";
  has "print(2 * 3)" "mul i64";
  has "print(9 / 3)" "sdiv i64";
  has "print(9 % 4)" "srem i64";
  has "let b = 1 < 2\nprint(b)" "icmp slt i64"

let test_control () =
  has "let x = 1\nif x < 0 { print(0) } else { print(1) }" "br i1 ";
  has "var n = 0\nwhile n < 3 { n = n + 1 }" "br label %bb"

let test_functions () =
  let ir = llvm "func add(_ a: Int, _ b: Int) -> Int { return a + b }\nprint(add(1, 2))" in
  Alcotest.(check bool) "defines @add returning i64" true (contains ir "define i64 @add(i64 ");
  Alcotest.(check bool) "calls @add" true (contains ir "call i64 @add(")

let () =
  Alcotest.run "irgen"
    [
      ("preamble", [ Alcotest.test_case "module preamble" `Quick test_preamble ]);
      ("memory", [ Alcotest.test_case "alloca/load/store" `Quick test_memory ]);
      ("opcodes", [ Alcotest.test_case "typed LLVM opcodes" `Quick test_opcodes ]);
      ("control", [ Alcotest.test_case "br / cond_br" `Quick test_control ]);
      ("functions", [ Alcotest.test_case "define + call" `Quick test_functions ]);
    ]
