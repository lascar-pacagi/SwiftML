(* Alcotest unit tests for IRGen (concept 04).

   The headline correctness check for codegen is the *runtime* oracle (`make oracle`,
   compare stdout/exit vs swiftc). These unit tests are complementary: they pin the
   *shape* of the emitted LLVM IR, so a wrong opcode is caught and localized here rather
   than showing up as a wrong number at the end.

   They are also arranged so you can WORK INCREMENTALLY. `emit_llvm` is one function, but
   the groups below climb from "the module wrapper alone" to "whole programs", and each
   layer needs only what the layers before it needed:

     arithmetic  `gen_expr` ALONE — every program is a bare expression statement, so
                 no wrapper, no print, no slots are needed for this group to pass
     literals    the printf call, and that an immediate emits no instruction
     module      the wrapper: preamble, `define i32 @main`, `entry:`, `ret i32 0`
     slots       let/var: alloca, store, load, and slot REUSE
     (cram)      codegen.t builds and RUNS real programs — needs all of the above

   They are independent, so you can write `gen_expr` first, with an `emit_llvm` that is
   nothing but `... ; Buffer.contents buf`, and watch `arithmetic` go green while the rest
   is still red. Run one group at a time:

     dune exec ./phase1-minimal/04-codegen/tests/test_irgen.exe -- test module 0

   RED until you implement `irgen.ml : emit_llvm`; GREEN against `solution/irgen.ml`. *)

let emit (src : string) : string =
  let diags = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src diags)) diags) in
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

(* The instructions of `main`, with the module wrapper filtered out — comments, globals,
   `declare`, `define`, `entry:`, `ret i32 0`, `}`. Whatever is left is what your lowering
   emitted.

   This is how you test `gen_expr` BEFORE anything else exists. The filter does not
   require the wrapper to be there, so you can start with

     let emit_llvm prog = ... ; Buffer.contents buf     (* no preamble/main yet *)

   write `gen_expr`, and have the `arithmetic` groups pass while `module` and `literals`
   are still red. A bare expression statement (`1 + 2 * 3`) lowers to `ignore (gen_expr e)`
   and contributes nothing else, so the comparison below is exact, not a grep. *)
let is_wrapper (l : string) : bool =
  l = "" || l = "}" || l = "entry:" || l = "ret i32 0"
  || String.length l > 0 && (l.[0] = ';' || l.[0] = '@')
  || (String.length l >= 7 && String.sub l 0 7 = "declare")
  || (String.length l >= 6 && String.sub l 0 6 = "define")

let body (src : string) : string list =
  String.split_on_char '\n' (emit src) |> List.map String.trim
  |> List.filter (fun l -> not (is_wrapper l))

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

(* --- layer 2: arithmetic ------------------------------------------------------------
   Every program here is a BARE expression statement, which lowers to `ignore (gen_expr e)`.
   So this whole group needs `gen_expr` and nothing else — not the module wrapper, not the
   print call, not the slot map. Write `gen_expr` first and these go green first. *)
let test_opcodes () =
  has "1 + 2" "add i64";
  has "3 - 1" "sub i64";
  has "2 * 3" "mul i64";
  has "9 / 3" "sdiv i64";
  has "9 % 4" "srem i64";
  (* unary minus is lowered as 0 - x — LLVM has no integer negate *)
  has "-5" "sub i64 0,"

let test_signedness () =
  (* the signed-vs-unsigned choice matters for parity — never the unsigned forms *)
  lacks "9 / 3" "udiv";
  lacks "9 % 4" "urem"

let test_nesting () =
  (* post-order: the inner multiply is emitted BEFORE the add that consumes it *)
  Alcotest.(check int) "one mul" 1 (count "1 + 2 * 3" "mul i64");
  Alcotest.(check int) "one add" 1 (count "1 + 2 * 3" "add i64");
  (* deeper nesting still emits exactly one instruction per operator *)
  Alcotest.(check int) "four operators, four instructions" 4
    (List.length (body "1 + 2 * 3 - 4 / 2"))

(* Expressions ALONE, with nothing else in the program. `1 + 2 * 3` as a statement emits
   exactly what `gen_expr` emitted — so these compare the whole instruction sequence, which
   pins evaluation order, operand threading and the fresh-name discipline in one go. *)
let test_expr_alone () =
  Alcotest.(check (list string)) "a literal alone emits nothing" [] (body "42");
  Alcotest.(check (list string))
    "one operator, one instruction" [ "%t1 = add i64 1, 2" ] (body "1 + 2");
  Alcotest.(check (list string))
    "inner first, and its register feeds the outer"
    [ "%t1 = mul i64 2, 3"; "%t2 = add i64 1, %t1" ]
    (body "1 + 2 * 3");
  Alcotest.(check (list string))
    "left-to-right within a level"
    [ "%t1 = mul i64 2, 3"; "%t2 = sdiv i64 8, 4"; "%t3 = add i64 %t1, %t2" ]
    (body "2 * 3 + 8 / 4");
  Alcotest.(check (list string))
    "unary minus is 0 - x, applied after its operand"
    [ "%t1 = mul i64 2, 3"; "%t2 = sub i64 0, %t1" ]
    (body "-(2 * 3)")

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
          Alcotest.test_case "opcode mapping (gen_expr only)" `Quick test_opcodes;
          Alcotest.test_case "signed div/rem, not unsigned" `Quick test_signedness;
          Alcotest.test_case "one instruction per operator" `Quick test_nesting;
          Alcotest.test_case "exact instruction sequence" `Quick test_expr_alone;
        ] );
      ( "slots",
        [
          Alcotest.test_case "alloca/store/load" `Quick test_slot_model;
          Alcotest.test_case "a var reuses its slot" `Quick test_slot_reuse;
        ] );
    ]
