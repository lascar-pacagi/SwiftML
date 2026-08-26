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

(* The instructions a program lowers to. Taken from the whole module, because §6's first
   exercise adds a pre-pass over the program inside `emit_llvm`, and folding `emit_stmt`
   here would step around it.

   For the same reason, every case below that asserts a SLOT uses a `var` that is actually
   reassigned: that is the one binding which needs memory in every variant of this
   lowering, so these tests hold whether or not you have done the exercises. *)
let stmts_of (src : string) : string list =
  let d = diags () in
  let prog = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  String.split_on_char '\n' (Irgen.emit_llvm prog)
  |> List.map String.trim
  |> List.filter (fun l ->
         not
           (l = "" || l = "}" || l = "entry:" || l = "ret i32 0"
           || (String.length l > 0 && (l.[0] = ';' || l.[0] = '@'))
           || (String.length l >= 7 && String.sub l 0 7 = "declare")
           || (String.length l >= 6 && String.sub l 0 6 = "define")))

(* whole-MODULE lowering — only the `module` group needs this *)
let emit (src : string) : string =
  let d = diags () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Irgen.emit_llvm p

let contains haystack needle =
  let n = String.length haystack and m = String.length needle in
  let rec go i = i + m <= n && (String.sub haystack i m = needle || go (i + 1)) in
  m = 0 || go 0

(* how many lines of [ls] contain [needle] *)
let n_with (needle : string) (ls : string list) : int =
  List.length (List.filter (fun l -> contains l needle) ls)

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

(* the instructions of `main`, with the module wrapper filtered out *)
let is_wrapper (l : string) : bool =
  l = "" || l = "}" || l = "entry:" || l = "ret i32 0"
  || (String.length l > 0 && (l.[0] = ';' || l.[0] = '@'))
  || (String.length l >= 7 && String.sub l 0 7 = "declare")
  || (String.length l >= 6 && String.sub l 0 6 = "define")

let body (src : string) : string list =
  String.split_on_char '\n' (emit src) |> List.map String.trim
  |> List.filter (fun l -> not (is_wrapper l))

let lines_of (src : string) : string list =
  String.split_on_char '\n' (emit src) |> List.map String.trim
  |> List.filter (fun l -> l <> "")

(* index of the first line satisfying [p], or -1 *)
let index_where (p : string -> bool) (ls : string list) : int =
  let rec go i = function [] -> -1 | l :: rest -> if p l then i else go (i + 1) rest in
  go 0 ls

let starts_with pre l =
  String.length l >= String.length pre && String.sub l 0 (String.length pre) = pre

(* the name an instruction defines: everything before " = ", or None for instructions
   that produce no value (`store`, a void call). Deliberately does NOT require the name
   to look like a register — checking that is the point of one of the tests. *)
let lhs_of (l : string) : string option =
  let n = String.length l in
  let rec go i =
    if i + 3 > n then None
    else if String.sub l i 3 = " = " then Some (String.sub l 0 i)
    else go (i + 1)
  in
  go 0

(* --- group `module`: emit_llvm, the whole file -------------------------------------
   Nothing here needs an expression: an EMPTY program is still a valid module with a
   `main` that returns 0. *)
let test_preamble () =
  has "" "declare i32 @printf(ptr, ...)";
  has "" "define i32 @main()";
  has "" "entry:";
  has "" "ret i32 0";
  (* the format string is a 6-byte C string: '%', 'l', 'l', 'd', '\n', NUL — the count
     and the escapes both have to be right, or clang rejects the module *)
  has "" "@.fmt = private unnamed_addr constant [6 x i8] c\"%lld\\0A\\00\"";
  (* an empty program emits no instructions at all *)
  Alcotest.(check (list string)) "empty program, empty body" [] (body "")

let test_module_shape () =
  (* exactly one function, one entry block, one return *)
  Alcotest.(check int) "one define" 1 (count "print(1)" "define ");
  Alcotest.(check int) "one entry label" 1 (count "print(1)" "entry:");
  Alcotest.(check int) "one ret" 1 (count "print(1)" "ret i32 0");
  let ls = lines_of "let a = 1\nprint(a)" in
  (* order: globals and declare before define; ret last; body inside *)
  Alcotest.(check bool) "@.fmt comes before define" true
    (index_where (starts_with "@.fmt") ls < index_where (starts_with "define") ls);
  Alcotest.(check bool) "declare comes before define" true
    (index_where (starts_with "declare") ls < index_where (starts_with "define") ls);
  Alcotest.(check string) "the module ends with the closing brace" "}"
    (List.nth ls (List.length ls - 1));
  Alcotest.(check string) "...preceded by the return" "ret i32 0"
    (List.nth ls (List.length ls - 2));
  (* Phase 1 has no control flow: nothing may branch *)
  lacks "let a = 1\nprint(a)" "br ";
  lacks "let a = 1\nprint(a)" "phi "

let test_statement_order () =
  (* statements are lowered in source order *)
  let ls = body "print(7)\nprint(9)" in
  let idx needle = index_where (fun l -> contains l needle) ls in
  Alcotest.(check bool) "the first print is emitted first" true (idx "i64 7" < idx "i64 9");
  Alcotest.(check bool) "both are there" true (idx "i64 7" >= 0 && idx "i64 9" >= 0)

(* --- group `literals`: immediates ----------------------------------------------------
   An integer literal is an OPERAND, not an instruction: it is written straight into the
   instruction that uses it. Getting this wrong (materialising `%t1 = add i64 0, 42`)
   still prints the right number, so only a test catches it. Needs `emit_expr` only. *)
let test_immediates () =
  Alcotest.(check string) "a literal returns itself" "42" (operand "42");
  Alcotest.(check (list string)) "...and emits nothing" [] (instrs "42");
  Alcotest.(check (list string)) "a big literal is passed through" [] (instrs "9007199254740993");
  Alcotest.(check string) "...unchanged" "9007199254740993" (operand "9007199254740993");
  (* literal operands appear verbatim inside the instruction that consumes them *)
  Alcotest.(check (list string)) "both operands are immediates" [ "%t1 = add i64 40, 2" ]
    (instrs "40 + 2");
  Alcotest.(check (list string)) "and on the right of a nested one"
    [ "%t1 = mul i64 2, 3"; "%t2 = add i64 %t1, 10" ] (instrs "2 * 3 + 10")

(* --- group `literals`: the print call ------------------------------------------------
   `print(x)` is a `Call` node, so this is still `emit_expr` — no module, no slots. *)
let test_print_call () =
  (* the variadic call type is repeated before the callee — clang rejects it otherwise *)
  Alcotest.(check (list string)) "the call shape"
    [ "%t1 = call i32 (ptr, ...) @printf(ptr @.fmt, i64 7)" ] (instrs "print(7)");
  (* the argument is evaluated first, and its register is what gets passed *)
  Alcotest.(check (list string)) "evaluate, then call"
    [ "%t1 = mul i64 6, 7"; "%t2 = call i32 (ptr, ...) @printf(ptr @.fmt, i64 %t1)" ]
    (instrs "print(6 * 7)");
  (* print is Void in Swift, so nothing consumes its result — and what printf hands back
     is an i32 (the character count), which would be ill-typed anywhere an i64 is wanted.
     So return an immediate, not that register. Which immediate is up to you. *)
  Alcotest.(check bool) "print's operand is not printf's i32 register" false
    (String.length (operand "print(1)") > 0 && (operand "print(1)").[0] = '%');
  (* one call per print, and the register counter keeps moving between them *)
  let c = Irgen.create () in
  ignore (Irgen.emit_expr c (parse_expr "print(1)"));
  ignore (Irgen.emit_expr c (parse_expr "print(2)"));
  let ls =
    String.split_on_char '\n' (Buffer.contents c.Irgen.buf)
    |> List.map String.trim
    |> List.filter (fun l -> l <> "")
  in
  Alcotest.(check int) "one call per print" 2 (n_with "call i32 (ptr, ...) @printf" ls)

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
  Alcotest.(check string) "an operator returns its register" "%t1" (operand "1 + 2");
  Alcotest.(check string) "nested: the OUTER register is returned" "%t2" (operand "1 + 2 * 3");
  Alcotest.(check string) "unary returns its own register" "%t2" (operand "-(2 * 3)")

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
  (* left-associativity is visible in the operand threading, not just the tree *)
  Alcotest.(check (list string))
    "a - b - c groups to the left"
    [ "%t1 = sub i64 10, 3"; "%t2 = sub i64 %t1, 2" ]
    (instrs "10 - 3 - 2");
  Alcotest.(check (list string))
    "parentheses group to the right"
    [ "%t1 = sub i64 3, 2"; "%t2 = sub i64 10, %t1" ]
    (instrs "10 - (3 - 2)");
  (* one instruction per operator, however deep *)
  Alcotest.(check int) "four operators, four instructions" 4
    (List.length (instrs "1 + 2 * 3 - 4 / 2"))

(* Every operator in one expression, with the exact sequence its precedence implies.
   `1 + 2 * 3 - 8 / 4 % 3` is 1 + 6 - ((8/4) % 3) = 5, and the instruction order is the
   proof: `*` `/` `%` bind tighter than `+` `-`, and each level runs left to right. *)
let test_all_operators () =
  Alcotest.(check (list string))
    "five binops and the precedence between them"
    [
      "%t1 = mul i64 2, 3";
      "%t2 = add i64 1, %t1";
      "%t3 = sdiv i64 8, 4";
      "%t4 = srem i64 %t3, 3";
      "%t5 = sub i64 %t2, %t4";
    ]
    (instrs "1 + 2 * 3 - 8 / 4 % 3");
  (* unary mixed in, including a negated parenthesised subtraction and a negated literal *)
  Alcotest.(check (list string))
    "unary around and inside a product"
    [
      "%t1 = sub i64 2, 5"; "%t2 = sub i64 0, %t1"; "%t3 = sub i64 0, 2";
      "%t4 = mul i64 %t2, %t3";
    ]
    (instrs "-(2 - 5) * -2")

(* Non-commutative operators: getting the operands the wrong way round still produces a
   plausible-looking module, and only the ANSWER is wrong. Pin the order, and pin that
   chains group to the left the way Swift's grammar says. *)
let test_operand_order () =
  Alcotest.(check (list string)) "subtraction keeps its order" [ "%t1 = sub i64 9, 4" ]
    (instrs "9 - 4");
  Alcotest.(check (list string)) "division keeps its order" [ "%t1 = sdiv i64 9, 3" ]
    (instrs "9 / 3");
  Alcotest.(check (list string)) "remainder keeps its order" [ "%t1 = srem i64 9, 4" ]
    (instrs "9 % 4");
  Alcotest.(check (list string))
    "a / b / c is (a / b) / c"
    [ "%t1 = sdiv i64 100, 5"; "%t2 = sdiv i64 %t1, 2" ]
    (instrs "100 / 5 / 2");
  Alcotest.(check (list string))
    "a %% b %% c is (a %% b) %% c"
    [ "%t1 = srem i64 10, 7"; "%t2 = srem i64 %t1, 2" ]
    (instrs "10 % 7 % 2");
  Alcotest.(check (list string))
    "parentheses override the grouping"
    [ "%t1 = add i64 3, 4"; "%t2 = mul i64 2, %t1"; "%t3 = mul i64 %t2, 5" ]
    (instrs "2 * (3 + 4) * 5")

(* A long expression: nothing special happens, which is the point — one instruction per
   operator, each consuming the previous register, and the LAST one is what is returned. *)
let test_deep_expression () =
  let src = "1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10" in
  let ls = instrs src in
  Alcotest.(check int) "nine operators, nine instructions" 9 (List.length ls);
  Alcotest.(check string) "the last register is returned" "%t9" (operand src);
  Alcotest.(check (list string)) "a left-leaning chain"
    [ "%t1 = add i64 1, 2"; "%t2 = add i64 %t1, 3" ]
    (List.filteri (fun i _ -> i < 2) ls);
  (* a wide, mixed expression: still one instruction per operator *)
  let wide = "(1 + 2) * (3 - 4) / (5 % 6) - (7 + 8) * (9 - 10)" in
  (* + - % * / + - * -  = nine operators, however they are parenthesised *)
  Alcotest.(check int) "nine operators, nine instructions" 9 (List.length (instrs wide))

(* Literals at the edges of the grammar. *)
let test_literal_edges () =
  Alcotest.(check (list string)) "zero is an operand like any other" [ "%t1 = add i64 0, 0" ]
    (instrs "0 + 0");
  Alcotest.(check (list string)) "double negation is two instructions"
    [ "%t1 = sub i64 0, 5"; "%t2 = sub i64 0, %t1" ] (instrs "-(-5)");
  Alcotest.(check string) "a lone zero returns itself" "0" (operand "0");
  (* no instruction is invented to materialise a constant *)
  Alcotest.(check (list string)) "a bare literal emits nothing" [] (instrs "1000000")

let test_fresh_names () =
  (* every result gets a NAME OF ITS OWN — reusing one would break SSA, and LLVM would
     reject the module *)
  let ls = instrs "(1 + 2) * (3 + 4)" in
  Alcotest.(check int) "three operators, three instructions" 3 (List.length ls);
  let names = List.filter_map (fun l -> String.index_opt l ' ' |> Option.map (String.sub l 0)) ls in
  Alcotest.(check int) "three distinct result registers" 3
    (List.length (List.sort_uniq compare names));
  (* the counter lives in the ctx, so a second expression continues where the first left
     off instead of colliding with it *)
  let c = Irgen.create () in
  let a = Irgen.emit_expr c (parse_expr "1 + 1") in
  let b = Irgen.emit_expr c (parse_expr "2 + 2") in
  Alcotest.(check bool) "two expressions, two different registers" true (a <> b)

(* --- group `slots`: slot_of and emit_stmt -------------------------------------------
   These use `slot_of` and `emit_stmt` directly — the module wrapper is not involved. *)
(* Every value in LLVM is `%name` (local) or `@name` (global) or a literal. A bare
   identifier — `ptr x.addr` instead of `ptr %x.addr` — is not a value at all, and clang
   stops at "expected value token". These two cases check the shapes the counting tests
   above cannot see. *)
let test_well_formed_operands () =
  let bad_ptr l =
    (* "ptr " followed by anything that is not % or @ *)
    let rec go i =
      i + 4 <= String.length l
      && ((String.sub l i 4 = "ptr " && i + 4 < String.length l
           && l.[i + 4] <> '%' && l.[i + 4] <> '@')
         || go (i + 1))
    in
    go 0
  in
  List.iter
    (fun src ->
      List.iter
        (fun l ->
          Alcotest.(check bool)
            (Printf.sprintf "%S: pointer operands are registers, not bare names (%S)" src l)
            false (bad_ptr l))
        (stmts_of src))
    [ "let x = 5\nprint(x)"; "var v = 1\nv = v + 1\nprint(v)"; "let a = 1\nlet b = a + a" ];
  (* and the DESTINATION of every instruction is a register too: `x = load …` is a bare
     name where LLVM wants `%x`, and it stops at "expected instruction opcode" *)
  List.iter
    (fun src ->
      List.iter
        (fun l ->
          match lhs_of l with
          | Some d ->
              Alcotest.(check bool)
                (Printf.sprintf "%S: %S defines %S, which must start with '%%'" src l d)
                true
                (String.length d > 1 && d.[0] = '%')
          | None -> ())
        (stmts_of src))
    [ "let x = 5\nprint(x)"; "var v = 1\nv = v + 1\nprint(v)"; "let a = 1\nlet b = a + a" ];
  (* slot_of hands back a register, so its result can be used as an operand directly *)
  let c = Irgen.create () in
  let r = Irgen.slot_of c "x" in
  Alcotest.(check bool) (Printf.sprintf "slot_of returned %S, which must start with '%%'" r) true
    (String.length r > 1 && r.[0] = '%')

(* SSA in one line: a register is written once. `%t1 = alloca` followed by
   `%t1 = load` is the classic slip — reusing the slot's own register for the value
   loaded out of it. *)
let test_single_assignment () =
  List.iter
    (fun src ->
      let defs = List.filter_map lhs_of (stmts_of src) in
      Alcotest.(check int)
        (Printf.sprintf "%S: every register is defined exactly once" src)
        (List.length defs)
        (List.length (List.sort_uniq compare defs)))
    [
      "let x = 5\nprint(x)";
      "var v = 1\nv = v + 1\nprint(v)";
      "let a = 1\nlet b = 2\nprint(a + b + a)";
    ]

let test_slot_of () =
  (* the map is the point: the SAME name gives the same register, and allocates once *)
  let c = Irgen.create () in
  let r1 = Irgen.slot_of c "x" in
  let r2 = Irgen.slot_of c "x" in
  let r3 = Irgen.slot_of c "y" in
  Alcotest.(check string) "the same name gives the same slot" r1 r2;
  Alcotest.(check bool) "a different name gives a different slot" true (r1 <> r3);
  let ls =
    String.split_on_char '\n' (Buffer.contents c.Irgen.buf) |> List.map String.trim
    |> List.filter (fun l -> l <> "")
  in
  Alcotest.(check int) "two names, two allocas" 2 (n_with "alloca" ls)

let test_slot_model () =
  let ls = stmts_of "var x = 5\nx = x + 1\nprint(x)" in
  Alcotest.(check int) "one alloca for one binding" 1 (n_with "alloca i64" ls);
  Alcotest.(check int) "stored twice: the declaration and the assignment" 2
    (n_with "store i64" ls);
  Alcotest.(check int) "loaded at each use" 2 (n_with "load i64" ls);
  Alcotest.(check int) "two bindings, two allocas" 2
    (n_with "alloca i64" (stmts_of "var x = 1\nvar y = 2\nx = y\ny = x\nprint(x + y)"));
  (* the slot is allocated before it is stored into *)
  Alcotest.(check bool) "alloca precedes the store" true
    (index_where (fun l -> contains l "alloca") ls
    < index_where (fun l -> contains l "store") ls)

let test_slot_reuse () =
  (* reassignment must STORE into the existing slot, never allocate a second one *)
  let ls = stmts_of "var c = 1\nc = c * 2\nprint(c)" in
  Alcotest.(check int) "reassignment reuses the slot" 1 (n_with "alloca i64" ls);
  Alcotest.(check int) "...and stores twice into it" 2 (n_with "store i64" ls);
  (* every read of a slot is a load — the value is not cached across uses *)
  Alcotest.(check int) "each use loads" 3
    (n_with "load i64" (stmts_of "var x = 1\nx = x + 1\nprint(x + x)"));
  Alcotest.(check int) "...across statements too" 3
    (n_with "load i64" (stmts_of "var x = 1\nx = x + 1\nprint(x)\nprint(x)"))

let test_stmt_kinds () =
  (* a bare expression statement emits its instructions and drops the operand *)
  Alcotest.(check (list string)) "an expression statement still computes"
    [ "%t1 = add i64 1, 2" ] (stmts_of "1 + 2");
  (* a declaration stores its initializer's operand into the slot *)
  Alcotest.(check bool) "the stored value is the multiply's register" true
    (List.exists
       (fun l -> contains l "store i64 %t1")
       (stmts_of "var x = 6 * 7\nx = x + 1"));
  (* an assignment reads the right-hand side, computes, and stores last *)
  let ls = stmts_of "var v = 1\nv = v + 1" in
  let last_where p = List.length ls - 1 - index_where p (List.rev ls) in
  (* note the needle: "add" alone also matches the slot register `%v.addr` *)
  let add_at = index_where (fun l -> contains l "= add i64") ls in
  Alcotest.(check bool) "load, then add, then the store that ends the statement" true
    (index_where (fun l -> contains l "load i64") ls < add_at
    && add_at < last_where (starts_with "store"))

(* Many statements, and the slot bookkeeping that has to survive them. *)
let test_many_statements () =
  let src =
    "var a = 3\nvar b = 4\na = a * a + b * b\nb = a - b * 2\nprint(a)\nprint(b)\n\
     print(a % b + a / b)"
  in
  let ls = stmts_of src in
  Alcotest.(check int) "two names, two allocas" 2 (n_with "alloca i64" ls);
  (* two declarations plus two reassignments *)
  Alcotest.(check int) "four stores" 4 (n_with "store i64" ls);
  (* one load per READ: a,a,b,b then a,b then a then b then a,b,a,b *)
  Alcotest.(check int) "twelve loads" 12 (n_with "load i64" ls);
  Alcotest.(check int) "three calls" 3 (n_with "call i32 (ptr, ...) @printf" ls)

let () =
  Alcotest.run "irgen"
    [
      ( "module",
        [
          Alcotest.test_case "preamble + main + ret" `Quick test_preamble;
          Alcotest.test_case "module shape and ordering" `Quick test_module_shape;
          Alcotest.test_case "statements in source order" `Quick test_statement_order;
        ] );
      ( "literals",
        [
          Alcotest.test_case "immediates emit no instruction" `Quick test_immediates;
          Alcotest.test_case "the printf call" `Quick test_print_call;
        ] );
      ( "arithmetic",
        [
          Alcotest.test_case "opcode mapping (emit_expr alone)" `Quick test_opcodes;
          Alcotest.test_case "every operator in one expression" `Quick test_all_operators;
          Alcotest.test_case "operand order and associativity" `Quick test_operand_order;
          Alcotest.test_case "long and wide expressions" `Quick test_deep_expression;
          Alcotest.test_case "literal edges" `Quick test_literal_edges;
          Alcotest.test_case "what emit_expr returns" `Quick test_operands;
          Alcotest.test_case "signed div/rem, not unsigned" `Quick test_signedness;
          Alcotest.test_case "post-order + exact sequence" `Quick test_nesting;
          Alcotest.test_case "a fresh register per result" `Quick test_fresh_names;
        ] );
      ( "slots",
        [
          Alcotest.test_case "operands are well-formed values" `Quick test_well_formed_operands;
          Alcotest.test_case "every register defined once (SSA)" `Quick test_single_assignment;
          Alcotest.test_case "slot_of: one slot per name" `Quick test_slot_of;
          Alcotest.test_case "alloca/store/load" `Quick test_slot_model;
          Alcotest.test_case "a var reuses its slot" `Quick test_slot_reuse;
          Alcotest.test_case "each statement kind" `Quick test_stmt_kinds;
          Alcotest.test_case "a longer program's bookkeeping" `Quick test_many_statements;
        ] );
    ]
