(* Alcotest for concept 28: copy propagation (TODO(28)) and the GIVEN whole-module class
   devirtualization. The `pass alone` group runs copy_propagation on its own — the full `-O`
   may erase more after inlining, and separating the two is what makes the safety cases mean
   something. *)

let front (src : string) : Ast.program * Diagnostics.sink =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  (p, d)

let lower (src : string) : Sil.modul =
  let p, d = front src in
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  Silgen.lower p

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let is_copy = function Sil.Copy_value _ -> true | _ -> false
let is_destroy = function Sil.Destroy_value _ -> true | _ -> false
let is_dispatch = function Sil.Apply_class _ -> true | _ -> false

(* mem2reg then copy propagation, and nothing else — the pass on its own *)
let pass_alone (src : string) : Sil.modul =
  Opt.run_pipeline
    [ { Opt.name = "mem2reg"; run = Opt.mem2reg }; { Opt.name = "cp"; run = Opt.copy_propagation } ]
    (lower src)

let tracer = "class T { var id: Int\n  init(_ i: Int) { id = i } }\n"

(* ---- TODO(28): the removals ---- *)

let test_param_copy_removed () =
  let m = pass_alone (tracer ^ "func f(_ a: T) -> Int {\n  let c = a\n  return c.id\n}\nprint(f(T(5)))") in
  Alcotest.(check int) "the borrow-copy is gone" 0 (count_instr is_copy m)

let test_chain_removed () =
  let m = pass_alone (tracer ^ "func g(_ n: T) -> Int {\n  let a = n\n  let b = a\n  let c = b\n  return c.id\n}\nprint(g(T(2)))") in
  Alcotest.(check int) "chained copies all gone" 0 (count_instr is_copy m);
  Alcotest.(check int) "and their destroys with them" 1 (count_instr is_destroy m)

let test_owned_local_pair_removed () =
  (* `let a = T(1); let c = a` — the copy's destroy precedes a's, so a outlives the bracket *)
  let m = pass_alone (tracer ^ "func f() -> Int {\n  let a = T(1)\n  let c = a\n  return c.id\n}\nprint(f())") in
  Alcotest.(check int) "borrow-of-local pair gone" 0 (count_instr is_copy m)

let test_full_pipeline_agrees () =
  let m = Opt.optimize (lower (tracer ^ "func f(_ a: T) -> Int {\n  let c = a\n  return c.id\n}\nprint(f(T(5)))")) in
  Alcotest.(check int) "no copies survive -O either" 0 (count_instr is_copy m);
  Alcotest.(check (list string)) "and the module still verifies" [] (Sil.verify m)

(* ---- TODO(28): the cases that must NOT be rewritten ---- *)

let test_escaping_copy_kept () =
  (* the copy is RETURNED (consumed by return, not destroy): the PASS must keep it — it
     transfers ownership to the caller. The full -O may still erase it after INLINING exposes
     both ends of the transfer in one function; that composition is sound, which is exactly
     why this test runs the pass alone. *)
  let m = pass_alone (tracer ^ "func f(_ a: T) -> T {\n  return a\n}\nprint(f(T(7)).id)") in
  Alcotest.(check bool) "the transferring copy survives" true (count_instr is_copy m >= 1)

let test_overwritten_source_kept () =
  (* THE keep case: the copy's source is a load from a slot overwritten inside the bracket, so
     the copy is the object's only other +1 — deleting it would move a deinit *)
  let src =
    "class T { var id: Int\n  init(_ i: Int) { id = i }\n  deinit { print(id) } }\n\
     func f() {\n  var a = T(1)\n  let c = a\n  a = T(2)\n  print(c.id)\n  print(a.id)\n}\nf()"
  in
  Alcotest.(check bool) "the load-sourced copy survives the pass" true (count_instr is_copy (pass_alone src) >= 1);
  Alcotest.(check bool) "and survives the full -O" true (count_instr is_copy (Opt.optimize (lower src)) >= 1)

let test_balanced_traffic () =
  (* whatever remains stays balanced: every object is born at an alloc_ref or a copy_value and
     dies at exactly one destroy_value *)
  let m = Opt.optimize (lower (tracer ^ "func f(_ a: T) -> Int {\n  let c = a\n  return c.id\n}\nprint(f(T(5)))")) in
  let allocs = count_instr (function Sil.Alloc_ref _ -> true | _ -> false) m in
  Alcotest.(check int) "destroys = copies + allocs" (count_instr is_copy m + allocs) (count_instr is_destroy m)

(* ---- the GIVEN whole-module devirtualization ---- *)

let hier =
  "class A { var x: Int\n  init() { x = 1 }\n  func f() -> Int { return 1 } }\n\
   class B: A { override func f() -> Int { return 2 } }\n\
   class Solo { var y: Int\n  init() { y = 5 }\n  func g() -> Int { return y } }\n\
   func go(_ a: A) -> Int { return a.f() }\n\
   func solo(_ s: Solo) -> Int { return s.g() }\n"

let test_subclass_free_devirtualized () =
  let raw = lower (hier ^ "print(go(B()))\nprint(solo(Solo()))") in
  Alcotest.(check int) "two dispatches before" 2 (count_instr is_dispatch raw);
  let m = Opt.optimize (lower (hier ^ "print(go(B()))\nprint(solo(Solo()))")) in
  Alcotest.(check int) "only the overridden one after" 1 (count_instr is_dispatch m)

let test_override_hierarchy_kept () =
  (* adding a subclass to Solo takes its proof away — the property is whole-module *)
  let src =
    "class Solo { var y: Int\n  init() { y = 5 }\n  func g() -> Int { return y } }\n\
     class Grown: Solo { override func g() -> Int { return y * 2 } }\n\
     func solo(_ s: Solo) -> Int { return s.g() }\nprint(solo(Solo()))\nprint(solo(Grown()))"
  in
  Alcotest.(check int) "the dispatch stays" 1 (count_instr is_dispatch (Opt.optimize (lower src)))

let () =
  Alcotest.run "arcopt"
    [
      ( "removal 28",
        [ Alcotest.test_case "param borrow-copy" `Quick test_param_copy_removed;
          Alcotest.test_case "chained copies" `Quick test_chain_removed;
          Alcotest.test_case "owned-local pair" `Quick test_owned_local_pair_removed;
          Alcotest.test_case "the full -O agrees" `Quick test_full_pipeline_agrees ] );
      ( "safety 28",
        [ Alcotest.test_case "a returned copy is kept" `Quick test_escaping_copy_kept;
          Alcotest.test_case "an overwritten source" `Quick test_overwritten_source_kept;
          Alcotest.test_case "traffic stays balanced" `Quick test_balanced_traffic ] );
      ( "wmo devirt",
        [ Alcotest.test_case "no subclass, direct call" `Quick test_subclass_free_devirtualized;
          Alcotest.test_case "an override keeps its vtable" `Quick test_override_hierarchy_kept ] );
    ]
