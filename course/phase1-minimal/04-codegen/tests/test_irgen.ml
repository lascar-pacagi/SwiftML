(* Alcotest unit tests for IRGen (concept 04).

   The headline correctness check for codegen is the *runtime* oracle (`make oracle`,
   compare stdout/exit vs swiftc). These unit tests are complementary: they pin the
   *shape* of the emitted LLVM IR, so a wrong opcode is caught and localized here rather
   than showing up as a wrong number at the end.

   `irgen.ml` exposes its lowering steps, so each group tests ONE of them and you can
   write them in any order:

     arithmetic  Irgen.emit_expr, called directly — needs nothing else to exist
     literals    emit_expr's `print` case (the printf call)
     slots       Irgen.slot_of + Irgen.emit_stmt (alloca / store / load, and slot REUSE)
     module      Irgen.emit_llvm (the preamble, `define i32 @main`, `ret i32 0`)
     (cram)      codegen.t builds and RUNS real programs — needs all of the above

   Run one while you work on it:

     dune exec ./phase1-minimal/04-codegen/tests/test_irgen.exe -- test arithmetic

   RED until you implement `irgen.ml`; GREEN against `solution/irgen.ml`. *)

let diags () = Diagnostics.create ()

let parse_expr (src : string) : Ast.expr =
  let d = diags () in
  Parser.parse_expr (Parser.create (Lexer.tokenize (Lexer.create src d)) d)

(* emit_expr IN ISOLATION: lower one expression into a fresh context, and return both
   halves of its contract — the instructions it emitted, and the operand it handed back. *)
let lower (src : string) : string list * string =
  let c = Irgen.create () in
  let operand = Irgen.emit_expr c (parse_expr src) in
  let lines =
    String.split_on_char '\n' (Buffer.contents c.Irgen.buf)
    |> List.map String.trim
    |> List.filter (fun l -> l <> "")
  in
  (lines, operand)

let instrs (src : string) : string list = fst (lower src)
let operand (src : string) : string = snd (lower src)

(* whole-program lowering, for the groups that need it *)
let emit (src : string) : string =
  let d = diags () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Irgen.emit_llvm p

let contains haystack needle =
  let n = String.length haystack and m = String.length needle in
  let rec go i = i + m <= n && (String.sub haystack i m = needle || go (i + 1)) in
  m = 0 || go 0

let has src needle =
  Alcotest.(check bool) (Printf.sprintf "%S emits %S" src needle) true (contains (emit src) needle)

let lacks src needle =
  Alcotest.(check bool)
    (Printf.sprintf "%S must NOT emit %S" src needle)
    false (contains (emit src) needle)

(* count non-overlapping occurrences — how many allocas, how many loads *)
let count (src : string) (needle : string) : int =
  let s = emit src in
  let n = String.length s and m = String.length needle in
  let rec go i acc =
    if i + m > n then acc
    else if String.sub s i m = needle then go (i + m) (acc + 1)
    else go (i + 1) acc
  in
  go 0 0

(* --- group `module`: the wrapper -------------------------------------------------
   Nothing here needs an expression: an EMPTY program is still a valid module with a
   `main` that returns 0. Write this first — every later layer prints inside it. *)
let test_module () =
  has "" "declare i32 @printf(ptr, ...)";
  has "" "@.fmt";
  has "" "define i32 @main()";
  has "" "ret i32 0";
  (* the format string is a 6-byte C string: '%', 'l', 'l', 'd', '\n', NUL *)
  has "" "[6 x i8]";
  has "" "%lld";
  (* main's body is one basic block in Phase 1 *)
  has "" "entry:"

(* --- group `literals`: the print call ------------------------------------------
   `print(1)` is the smallest program with a statement in it. An integer literal is an
   IMMEDIATE — it needs no instruction of its own, it is just written into the operand. *)
let test_literals () =
  has "print(7)" "call i32 (ptr, ...) @printf";
  has "print(7)" "i64 7";
  (* a literal costs no instruction: no arithmetic, no memory traffic *)
  lacks "print(7)" "add i64";
  lacks "print(7)" "alloca";
  (* count CALLS, not the `declare` line, which also mentions @printf *)
  Alcotest.(check int) "one printf call per print" 2
    (count "print(1)\nprint(2)" "call i32 (ptr, ...) @printf")

(* --- group `arithmetic`: emit_expr, on its own ---------------------------------------
   These call `Irgen.emit_expr` directly, so they pass as soon as that one function is
   written — no module wrapper, no `print`, no slot map needed. *)
let test_opcodes () =
  let op src instr =
    Alcotest.(check (list string)) (Printf.sprintf "%S" src) [ instr ] (instrs src)
  in
  op "1 + 2" "%t1 = add i64 1, 2";
  op "3 - 1" "%t1 = sub i64 3, 1";
  op "2 * 3" "%t1 = mul i64 2, 3";
  op "9 / 3" "%t1 = sdiv i64 9, 3";
  op "9 % 4" "%t1 = srem i64 9, 4";
  (* unary minus is lowered as 0 - x — LLVM has no integer negate *)
  op "-5" "%t1 = sub i64 0, 5"

let test_operands () =
  (* the other half of emit_expr's contract: WHAT it returns *)
  Alcotest.(check string) "a literal returns itself, emitting nothing" "42" (operand "42");
  Alcotest.(check (list string)) "...nothing at all" [] (instrs "42");
  Alcotest.(check string) "an operator returns its register" "%t1" (operand "1 + 2");
  Alcotest.(check string) "nested: the OUTER register is returned" "%t2" (operand "1 + 2 * 3")

let test_signedness () =
  (* the signed-vs-unsigned choice matters for parity — never the unsigned forms *)
  Alcotest.(check bool) "no udiv" false (List.exists (fun l -> contains l "udiv") (instrs "9 / 3"));
  Alcotest.(check bool) "no urem" false (List.exists (fun l -> contains l "urem") (instrs "9 % 4"))

let test_nesting () =
  (* post-order, and the inner register threaded into the outer instruction *)
  Alcotest.(check (list string))
    "inner first, and its register feeds the outer"
    [ "%t1 = mul i64 2, 3"; "%t2 = add i64 1, %t1" ]
    (instrs "1 + 2 * 3");
  Alcotest.(check (list string))
    "left-to-right within a level"
    [ "%t1 = mul i64 2, 3"; "%t2 = sdiv i64 8, 4"; "%t3 = add i64 %t1, %t2" ]
    (instrs "2 * 3 + 8 / 4");
  Alcotest.(check (list string))
    "unary applies after its operand"
    [ "%t1 = mul i64 2, 3"; "%t2 = sub i64 0, %t1" ]
    (instrs "-(2 * 3)");
  (* one instruction per operator, however deep *)
  Alcotest.(check int) "four operators, four instructions" 4
    (List.length (instrs "1 + 2 * 3 - 4 / 2"))

(* --- group `slots`: the slot model -------------------------------------------------------- *)
let test_slot_model () =
  has "let x = 5\nprint(x)" "alloca i64";
  has "let x = 5\nprint(x)" "store i64";
  has "let x = 5\nprint(x)" "load i64";
  (* one binding, one slot *)
  Alcotest.(check int) "one alloca for one binding" 1 (count "let x = 5\nprint(x)" "alloca");
  Alcotest.(check int) "two bindings, two allocas" 2
    (count "let x = 1\nlet y = 2\nprint(x + y)" "alloca")

let test_slot_reuse () =
  (* reassignment must STORE into the existing slot, never allocate a second one *)
  Alcotest.(check int) "reassignment reuses the slot" 1
    (count "var c = 1\nc = c * 2\nprint(c)" "alloca");
  Alcotest.(check int) "...and stores twice into it" 2
    (count "var c = 1\nc = c * 2\nprint(c)" "store i64");
  (* every read of a binding is a load — the value is not cached across statements *)
  Alcotest.(check int) "each use loads" 2 (count "let x = 1\nprint(x + x)" "load i64")

let () =
  Alcotest.run "irgen"
    [
      ("module", [ Alcotest.test_case "the wrapper: preamble, main, ret" `Quick test_module ]);
      ( "literals",
        [ Alcotest.test_case "immediates + the printf call" `Quick test_literals ] );
      ( "arithmetic",
        [
          Alcotest.test_case "opcode mapping (emit_expr alone)" `Quick test_opcodes;
          Alcotest.test_case "what emit_expr returns" `Quick test_operands;
          Alcotest.test_case "signed div/rem, not unsigned" `Quick test_signedness;
          Alcotest.test_case "post-order + exact sequence" `Quick test_nesting;
        ] );
      ( "slots",
        [
          Alcotest.test_case "alloca/store/load" `Quick test_slot_model;
          Alcotest.test_case "a var reuses its slot" `Quick test_slot_reuse;
        ] );
    ]
