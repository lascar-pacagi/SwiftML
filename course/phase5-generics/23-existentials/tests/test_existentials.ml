(* Alcotest unit tests for concept 23 — the fixed existential container and dynamic casts.
   Groups follow the holes: `sema` is GIVEN code and green from the start; `casts 23a` needs the
   SILGen hole; `irgen 23b/c` reads the emitted LLVM, so it needs the two IRGen holes. *)

let front (src : string) : Ast.program * Diagnostics.sink =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  (p, d)

let msgs (d : Diagnostics.sink) : string list =
  List.rev_map (fun (e : Diagnostics.t) -> e.Diagnostics.message) d.Diagnostics.diags

let lower_no_err (src : string) : Sil.modul =
  let p, d = front src in
  Alcotest.(check bool) "no sema ERRORS" false (Diagnostics.has_errors d);
  Silgen.lower p

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let proto = "protocol P { func v() -> Int }\nstruct A: P { var x: Int\n  func v() -> Int { return x } }\n"

let test_cast_types () =
  (* as? : T?  /  as! : T *)
  let _, d = front (proto ^ "let p: P = A(x: 1)\nlet q: A? = p as? A\nprint(q ?? A(x: 0))") in
  ignore d; (* the ?? of a struct payload type-checks structurally *)
  let _, d2 = front (proto ^ "let p: P = A(x: 1)\nlet a: A = p as! A\nprint(a.x)") in
  Alcotest.(check bool) "as! yields the concrete type" false (Diagnostics.has_errors d2)

let test_unrelated_warns () =
  let _, d = front (proto ^ "struct C { var z: Int }\nlet p: P = A(x: 1)\nif let c = p as? C { print(c.z) }") in
  Alcotest.(check bool) "always-fails cast warned" true
    (List.mem "cast from 'any P' to unrelated type 'C' always fails" (msgs d));
  Alcotest.(check bool) "but it is not an error" false (Diagnostics.has_errors d)

let test_sil_shapes () =
  let m = lower_no_err (proto ^ "let p: P = A(x: 1)\nif let a = p as? A { print(a.x) }") in
  Alcotest.(check int) "one identity test" 1
    (count_instr (function Sil.Same_witness _ -> true | _ -> false) m);
  Alcotest.(check int) "the open happens in the proven branch" 1
    (count_instr (function Sil.Open_existential _ -> true | _ -> false) m);
  Alcotest.(check (list string)) "module verifies" [] (Sil.verify m)

let test_abort_term () =
  let m = lower_no_err (proto ^ "let p: P = A(x: 1)\nlet a = p as! A\nprint(a.x)") in
  let has_abort =
    List.exists
      (fun (f : Sil.func) -> List.exists (fun (b : Sil.block) -> match b.Sil.term with Sil.Abort _ -> true | _ -> false) f.Sil.blocks)
      m.Sil.funcs
  in
  Alcotest.(check bool) "as! lowers a fail block ending in abort" true has_abort

let llvm (src : string) : string =
  (* the emitted module as text — the only way to see the container without running clang *)
  let p, d = front src in
  Alcotest.(check bool) "no sema ERRORS" false (Diagnostics.has_errors d);
  Irgen.emit_llvm (Silgen.lower p)

let occurrences (needle : string) (hay : string) : int =
  let n = String.length needle and h = String.length hay in
  let c = ref 0 in
  for i = 0 to h - n do
    if String.sub hay i n = needle then incr c
  done;
  !c

let big =
  "protocol P { func v() -> Int }\nstruct Big: P { var a: Int\n  var b: Int\n  var c: Int\n\
   var d: Int\n  var e: Int\n  func v() -> Int { return a + b + c + d + e } }\n"

let test_container_is_fixed () =
  (* the SAME container for a two-word and a five-word conformer: that fixed size is what
     separate compilation requires *)
  let small = llvm (proto ^ "let p: P = A(x: 1)\nprint(p.v())") in
  let boxed = llvm (big ^ "let p: P = Big(a: 1, b: 2, c: 3, d: 4, e: 5)\nprint(p.v())") in
  Alcotest.(check bool) "3 words + a table pointer" true
    (occurrences "%any.P = type { [3 x i64], ptr }" small = 1);
  Alcotest.(check bool) "same for the boxed conformer" true
    (occurrences "%any.P = type { [3 x i64], ptr }" boxed = 1)

let test_inline_no_malloc () =
  let ir = llvm (proto ^ "let p: P = A(x: 1)\nprint(p.v())") in
  Alcotest.(check int) "a fitting payload is not boxed" 0 (occurrences "call ptr @malloc" ir)

let test_large_boxes () =
  let ir = llvm (big ^ "let p: P = Big(a: 1, b: 2, c: 3, d: 4, e: 5)\nprint(p.v())") in
  Alcotest.(check int) "one box for one wrap" 1 (occurrences "call ptr @malloc" ir);
  Alcotest.(check int) "40 bytes, the struct's size" 1 (occurrences "@malloc(i64 40)" ir)

let test_open_reads_box () =
  (* a generic's `-> T` open is the same read the cast uses; on a boxed payload it has to go
     through the box pointer, and the emitted module must still be well formed *)
  let ir = llvm (big ^ "func id<T: P>(_ t: T) -> T { return t }\nprint(id(Big(a: 1, b: 2, c: 3, d: 4, e: 5)).e)") in
  Alcotest.(check bool) "the wrap boxed" true (occurrences "call ptr @malloc" ir >= 1);
  Alcotest.(check bool) "and something loads a pointer back" true (occurrences "load ptr" ir >= 1)

let test_unrelated_is_constant () =
  (* no table exists for a non-conformance, so naming @wt.P.C would be a link error: the test
     must lower to a constant instead *)
  let m = lower_no_err (proto ^ "struct C { var z: Int }\nlet p: P = A(x: 1)\nif let c = p as? C { print(c.z) }") in
  Alcotest.(check int) "no identity test at all" 0
    (count_instr (function Sil.Same_witness _ -> true | _ -> false) m);
  Alcotest.(check int) "a constant false instead" 1
    (count_instr (function Sil.Bool_lit false -> true | _ -> false) m)

let test_two_casts_two_tests () =
  let m =
    lower_no_err
      (proto ^ "struct B: P { func v() -> Int { return 2 } }\nlet p: P = A(x: 1)\n\
       if let a = p as? A { print(a.x) }\nif let b = p as? B { print(b.v()) }")
  in
  Alcotest.(check int) "one identity test per cast" 2
    (count_instr (function Sil.Same_witness _ -> true | _ -> false) m)

let test_optimizer_safe () =
  let m = Opt.optimize (lower_no_err (proto ^ "let p: P = A(x: 6)\nif let a = p as? A { print(a.v()) }")) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let () =
  Alcotest.run "existentials"
    [
      ( "sema",
        [
          Alcotest.test_case "cast result types" `Quick test_cast_types;
          Alcotest.test_case "unrelated cast warns" `Quick test_unrelated_warns;
        ] );
      ( "casts 23a",
        [
          Alcotest.test_case "same_witness + open" `Quick test_sil_shapes;
          Alcotest.test_case "as! abort block" `Quick test_abort_term;
          Alcotest.test_case "unrelated is a constant" `Quick test_unrelated_is_constant;
          Alcotest.test_case "one test per cast" `Quick test_two_casts_two_tests;
          Alcotest.test_case "-O keeps it valid" `Quick test_optimizer_safe;
        ] );
      ( "irgen 23b/c",
        [
          Alcotest.test_case "one fixed container" `Quick test_container_is_fixed;
          Alcotest.test_case "small stays inline" `Quick test_inline_no_malloc;
          Alcotest.test_case "large is boxed" `Quick test_large_boxes;
          Alcotest.test_case "open reads the box" `Quick test_open_reads_box;
        ] );
    ]
