(* Alcotest unit tests for concept 24 — devirtualization and generic specialization.
   The two holes are separate module passes, so each group calls ITS pass directly rather than
   the whole `-O` pipeline: `devirt 24a` needs only `devirt_module`, `specialize 24b` only
   `specialize_module`. The `pipeline` group runs the real `optimize`, which needs both. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  Silgen.lower p

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let is_witness = function Sil.Apply_witness _ -> true | _ -> false
let is_open = function Sil.Open_existential _ -> true | _ -> false
let is_same = function Sil.Same_witness _ -> true | _ -> false
let has_fn n (m : Sil.modul) = List.exists (fun (f : Sil.func) -> f.Sil.fname = n) m.Sil.funcs

(* devirt reads SSA def-chains, so the two module passes are fed post-mem2reg SIL — the same
   order `optimize` uses *)
let ssa (m : Sil.modul) = Opt.run_pipeline [ { Opt.name = "mem2reg"; run = Opt.mem2reg } ] m

let proto = "protocol P { func v() -> Int }\nstruct A: P { var x: Int\n  func v() -> Int { return x } }\n"
let two = proto ^ "struct B: P { func v() -> Int { return 7 } }\n"

(* ---------------------------------------------------------------- TODO(24a): devirt *)

let test_devirt_dispatch () =
  (* a dispatch on a locally-built existential is provable, so it folds to a direct call *)
  let m = ssa (lower (proto ^ "let s: P = A(x: 21)\nprint(s.v())")) in
  Alcotest.(check int) "raw SIL dispatches dynamically" 1 (count_instr is_witness m);
  let m = Opt.devirt_module m in
  Alcotest.(check int) "no witness dispatch survives" 0 (count_instr is_witness m);
  Alcotest.(check (list string)) "still valid SIL" [] (Sil.verify m)

let test_devirt_unprovable () =
  (* two tables reach this dispatch, so the pass must leave it alone *)
  let m =
    ssa (lower (two ^ "func h(_ e: P) -> Int { return e.v() }\nvar e: P = A(x: 1)\nif 1 < 2 { e = B() }\nprint(h(e))"))
  in
  let m = Opt.devirt_module m in
  Alcotest.(check bool) "dynamic dispatch survives" true (count_instr is_witness m >= 1);
  Alcotest.(check (list string)) "still valid SIL" [] (Sil.verify m)

let test_devirt_identity () =
  (* a proven wrap turns the identity test into a constant, which simplify_cfg then folds *)
  let m = ssa (lower (two ^ "let p: P = A(x: 5)\nif let a = p as? A { print(a.x) } else { print(-1) }")) in
  Alcotest.(check int) "raw SIL tests the table" 1 (count_instr is_same m);
  let m = Opt.devirt_module m in
  Alcotest.(check int) "the test became a constant" 0 (count_instr is_same m)

let test_devirt_open () =
  (* the open of a PROVEN existential becomes an alias for the payload it would have copied.
     A cast's open is the one devirt can fold on its own: the operand is the wrap itself. The
     open of a generic's `-> T` result needs specialization first, so it is not this test. *)
  let m = ssa (lower (two ^ "let p: P = A(x: 5)\nif let a = p as? A { print(a.x) } else { print(-1) }")) in
  Alcotest.(check bool) "raw SIL opens on the proven branch" true (count_instr is_open m >= 1);
  let m = Opt.devirt_module m in
  Alcotest.(check int) "no open survives" 0 (count_instr is_open m)

(* ---------------------------------------------------------------- TODO(24b): specialize *)

let test_clone_per_type () =
  let m = ssa (lower (two ^ "func g<T: P>(_ t: T) -> Int { return t.v() * 2 }\nprint(g(A(x: 3)) + g(B()))")) in
  let m = Opt.specialize_module m in
  Alcotest.(check bool) "a clone for A" true (has_fn "g$A" m);
  Alcotest.(check bool) "a clone for B" true (has_fn "g$B" m);
  Alcotest.(check (list string)) "still valid SIL" [] (Sil.verify m)

let test_clone_is_retyped () =
  (* the clone's parameter is the concrete struct, not the constraint's existential *)
  let m = ssa (lower (proto ^ "func dbl<T: P>(_ t: T) -> Int { return t.v() + t.v() }\nprint(dbl(A(x: 1)))")) in
  let m = Opt.specialize_module m in
  let clone = List.find (fun (f : Sil.func) -> f.Sil.fname = "dbl$A") m.Sil.funcs in
  Alcotest.(check (list string)) "parameter retyped to $A" [ "A" ]
    (List.map (fun (_, t) -> Types.string_of_ty t) clone.Sil.params)

let test_recursive_clone () =
  let m =
    ssa (lower (proto ^ "func rep<T: P>(_ t: T, _ n: Int) -> Int {\n  if n == 0 { return 0 }\n  return t.v() + rep(t, n - 1)\n}\nprint(rep(A(x: 5), 4))"))
  in
  let m = Opt.specialize_module m in
  Alcotest.(check bool) "the clone exists" true (has_fn "rep$A" m);
  let clone = List.find (fun (f : Sil.func) -> f.Sil.fname = "rep$A" ) m.Sil.funcs in
  let calls_itself =
    List.exists
      (fun (b : Sil.block) -> List.exists (fun (_, i) -> i = Sil.Func_ref "rep$A") b.Sil.instrs)
      clone.Sil.blocks
  in
  Alcotest.(check bool) "and it recurses into itself" true calls_itself

let test_nongeneric_not_cloned () =
  let m = ssa (lower (proto ^ "func h(_ e: P) -> Int { return e.v() }\nprint(h(A(x: 2)))")) in
  let m = Opt.specialize_module m in
  Alcotest.(check bool) "no h$A clone" false (has_fn "h$A" m);
  Alcotest.(check bool) "the original is untouched" true (has_fn "h" m)

let test_erased_original_kept () =
  (* the erased copy stays in the module: a caller that could not be proved still needs it *)
  let m =
    ssa (lower (proto ^ "func inner<T: P>(_ t: T) -> Int { return t.v() }\nfunc outer<T: P>(_ t: T) -> Int { return inner(t) + 1 }\nprint(outer(A(x: 3)))"))
  in
  let m = Opt.specialize_module m in
  Alcotest.(check bool) "outer specialized" true (has_fn "outer$A" m);
  Alcotest.(check bool) "the erased inner survives" true (has_fn "inner" m)

(* ---------------------------------------------------------------- the whole `-O` pipeline *)

let test_pipeline_cascade () =
  (* specialize -> devirt -> inline -> GVN: the clone ends as one extract and one binop *)
  let m = Opt.optimize (lower (proto ^ "func dbl<T: P>(_ t: T) -> Int { return t.v() + t.v() }\nprint(dbl(A(x: 10)))")) in
  Alcotest.(check bool) "the clone exists" true (has_fn "dbl$A" m);
  Alcotest.(check int) "no dispatch anywhere" 0 (count_instr is_witness m);
  Alcotest.(check int) "no wrap anywhere" 0
    (count_instr (function Sil.Init_existential _ -> true | _ -> false) m);
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let test_pipeline_keeps_unprovable () =
  let m =
    Opt.optimize (lower (two ^ "func h(_ e: P) -> Int { return e.v() }\nvar e: P = A(x: 1)\nif 1 < 2 { e = B() }\nprint(h(e))"))
  in
  Alcotest.(check bool) "dynamic dispatch survives where unprovable" true (count_instr is_witness m >= 1);
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let () =
  Alcotest.run "spec"
    [
      ( "devirt 24a",
        [
          Alcotest.test_case "known wrap, direct call" `Quick test_devirt_dispatch;
          Alcotest.test_case "unprovable stays dynamic" `Quick test_devirt_unprovable;
          Alcotest.test_case "identity test folds" `Quick test_devirt_identity;
          Alcotest.test_case "open becomes an alias" `Quick test_devirt_open;
        ] );
      ( "spec 24b",
        [
          Alcotest.test_case "a clone per concrete type" `Quick test_clone_per_type;
          Alcotest.test_case "the clone is retyped" `Quick test_clone_is_retyped;
          Alcotest.test_case "recursion self-specializes" `Quick test_recursive_clone;
          Alcotest.test_case "non-generic not cloned" `Quick test_nongeneric_not_cloned;
          Alcotest.test_case "erased original survives" `Quick test_erased_original_kept;
        ] );
      ( "pipeline",
        [
          Alcotest.test_case "the cascade erases it all" `Quick test_pipeline_cascade;
          Alcotest.test_case "unprovable kept under -O" `Quick test_pipeline_keeps_unprovable;
        ] );
    ]
