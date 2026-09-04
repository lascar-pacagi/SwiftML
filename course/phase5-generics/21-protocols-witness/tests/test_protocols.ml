(* Alcotest unit tests for concept 21 — protocols, conformance, witness tables, dispatch.
   One group per TODO hole, so a half-finished concept still reads: the `conformance` group
   needs only `TODO(21-sema)`, `tables` only `TODO(21c)`, `wrap` 21c+21a, `dispatch` all three.
   The `subset` group covers the GIVEN front-end rules that keep an aggregate out of IRGen. *)

let front (src : string) : Ast.program * Diagnostics.sink =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  (p, d)

let msgs (d : Diagnostics.sink) : string list =
  List.rev_map (fun (e : Diagnostics.t) -> e.Diagnostics.message) d.Diagnostics.diags

let lower (src : string) : Sil.modul =
  let p, d = front src in
  Alcotest.(check (list string)) "no sema errors" [] (msgs d);
  Silgen.lower p

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let wraps = count_instr (function Sil.Init_existential _ -> true | _ -> false)
let dispatches = count_instr (function Sil.Apply_witness _ -> true | _ -> false)
let has msg d = List.mem msg (msgs d)

let good =
  "protocol P { func v() -> Int }\nstruct A: P { var x: Int\n  func v() -> Int { return x } }\n\
   struct B: P { func v() -> Int { return 7 } }\nlet p: P = A(x: 1)\nprint(p.v())"

(* ---------------------------------------------------------------- TODO(21-sema) *)

let test_conformance_ok () =
  let _, d = front good in
  Alcotest.(check (list string)) "conforming program accepted" [] (msgs d)

let test_conformance_missing () =
  let _, d = front "protocol P { func v() -> Int }\nstruct A: P { var x: Int }" in
  Alcotest.(check bool) "missing method rejected" true (has "type 'A' does not conform to protocol 'P'" d)

let test_conformance_wrong_sig () =
  let _, d = front "protocol P { func v() -> Int }\nstruct A: P { func v() -> Bool { return true } }" in
  Alcotest.(check bool) "wrong return type rejected" true (has "type 'A' does not conform to protocol 'P'" d)

let test_conformance_wrong_param () =
  let _, d = front "protocol P { func v(_ k: Int) -> Int }\nstruct A: P { func v(_ k: Bool) -> Int { return 1 } }" in
  Alcotest.(check bool) "wrong parameter type rejected" true (has "type 'A' does not conform to protocol 'P'" d)

let test_conformance_extra_ok () =
  (* requirement ORDER is irrelevant and extra methods are allowed: only the set matters *)
  let _, d =
    front
      "protocol P {\n  func a() -> Int\n  func b() -> Bool\n}\n\
       struct A: P {\n  func extra() -> Int { return 0 }\n  func b() -> Bool { return true }\n  func a() -> Int { return 1 }\n}"
  in
  Alcotest.(check (list string)) "reordered + extra still conforms" [] (msgs d)

let test_conformance_two_protos () =
  let _, d = front "protocol P { func p() -> Int }\nprotocol Q { func q() -> Int }\nstruct B: P, Q { func p() -> Int { return 1 } }" in
  Alcotest.(check bool) "P holds" false (has "type 'B' does not conform to protocol 'P'" d);
  Alcotest.(check bool) "Q fails" true (has "type 'B' does not conform to protocol 'Q'" d)

let test_coercion_uses_predicate () =
  (* the same predicate gates the implicit wrap; swiftc words it per site *)
  let _, d =
    front
      "protocol P { func v() -> Int }\nstruct A: P { func v() -> Int { return 1 } }\nstruct D { var x: Int }\n\
       func g() -> P { return D(x: 1) }\nlet s: P = D(x: 1)"
  in
  Alcotest.(check bool) "return site" true (has "return expression of type 'D' does not conform to 'P'" d);
  Alcotest.(check bool) "let site" true (has "value of type 'D' does not conform to specified type 'P'" d)

(* ---------------------------------------------------------------- TODO(21c): the tables *)

let test_witness_tables () =
  let m = lower good in
  Alcotest.(check int) "two conformances -> two tables" 2 (List.length m.Sil.wtables);
  Alcotest.(check bool) "A's table points at A.v" true (List.mem ("P", "A", [ "A.v" ]) m.Sil.wtables);
  Alcotest.(check bool) "B's table points at B.v" true (List.mem ("P", "B", [ "B.v" ]) m.Sil.wtables);
  Alcotest.(check (list string)) "module verifies (tables reference real functions)" [] (Sil.verify m)

let test_table_slot_order () =
  (* the slot numbering is the REQUIREMENT order, not the order the methods were written *)
  let m =
    lower
      "protocol P {\n  func a() -> Int\n  func b() -> Int\n}\n\
       struct S: P {\n  func b() -> Int { return 2 }\n  func a() -> Int { return 1 }\n}\nprint(1)"
  in
  Alcotest.(check bool) "slots follow the protocol" true (List.mem ("P", "S", [ "S.a"; "S.b" ]) m.Sil.wtables)

let test_table_only_on_clause () =
  (* a struct with a matching method but no `: P` clause is not a conformance *)
  let m = lower "protocol P { func v() -> Int }\nstruct L {\n  var r: Int\n  func v() -> Int { return r } }\nprint(L(r: 1).r)" in
  Alcotest.(check int) "no clause, no table" 0 (List.length m.Sil.wtables)

(* ---------------------------------------------------------------- TODO(21a): the wrap *)

let test_wrap_once_per_concrete () =
  Alcotest.(check int) "one concrete coercion, one wrap" 1 (wraps (lower good))

let test_wrap_skips_existential () =
  (* `any P` -> `any P` is a move, not a re-wrap *)
  let m =
    lower
      "protocol P { func v() -> Int }\nstruct A: P { func v() -> Int { return 1 } }\n\
       func same(_ p: P) -> P { return p }\nlet a: P = A()\nlet b: P = a\nprint(same(b).v())"
  in
  Alcotest.(check int) "one wrap for one concrete value" 1 (wraps m)

let test_wrap_optional_payload () =
  (* `P?` wraps the payload into `any P` FIRST, then tags it `.some` — storing the raw struct
     in the payload slot was a real miscompile *)
  let m =
    lower
      "protocol P { func v() -> Int }\nstruct A: P { func v() -> Int { return 1 } }\n\
       let o: P? = A()\nif let p = o { print(p.v()) }"
  in
  Alcotest.(check int) "the payload is wrapped" 1 (wraps m)

(* ---------------------------------------------------------------- TODO(21b): dispatch *)

let test_dispatch_dynamic () =
  Alcotest.(check int) "existential receiver dispatches" 1 (dispatches (lower good))

let test_dispatch_static () =
  let m = lower "struct C { var r: Int\n  func a() -> Int { return r } }\nprint(C(r: 4).a())" in
  Alcotest.(check int) "concrete receiver stays static" 0 (dispatches m)

let test_dispatch_slot () =
  (* the slot in the dispatch is the requirement index, not the conformer's method index *)
  let m =
    lower
      "protocol P {\n  func a() -> Int\n  func b() -> Int\n}\n\
       struct S: P {\n  func b() -> Int { return 2 }\n  func a() -> Int { return 1 }\n}\n\
       let s: P = S()\nprint(s.b())"
  in
  let slots =
    List.concat_map
      (fun (f : Sil.func) ->
        List.concat_map
          (fun (b : Sil.block) ->
            List.filter_map (fun (_, i) -> match i with Sil.Apply_witness (_, k, _) -> Some k | _ -> None) b.Sil.instrs)
          f.Sil.blocks)
      m.Sil.funcs
  in
  Alcotest.(check (list int)) "b is requirement #1" [ 1 ] slots

(* ---------------------------------------------------------------- the optimizer *)

let test_optimizer_safe () =
  let m = Opt.optimize (lower good) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m);
  Alcotest.(check bool) "witness impls survive -O (reachable via the table)" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "A.v") m.Sil.funcs)

let test_optimizer_keeps_types () =
  (* the shipped GVN bug: `struct () $Zero` and `struct () $One` had the same value key, so the
     two wraps were merged and both calls dispatched through one table *)
  let m =
    Opt.optimize
      (lower
         "protocol N { func v() -> Int }\nstruct Zero: N { func v() -> Int { return 0 } }\n\
          struct One: N { func v() -> Int { return 1 } }\nfunc show(_ n: N) { print(n.v()) }\nshow(Zero())\nshow(One())")
  in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m);
  Alcotest.(check int) "both wraps survive" 2 (wraps m)

(* ---------------------------------------------------------------- the given subset rules *)

let test_subset_print () =
  let _, d = front "protocol P { func v() -> Int }\nstruct A: P { func v() -> Int { return 1 } }\nlet p: P = A()\nprint(p)" in
  Alcotest.(check bool) "print of an existential refused" true
    (has "cannot print a value of type 'any P' (only Int, Double, Bool and String)" d)

let test_subset_print_struct () =
  let _, d = front "struct P {\n  var x: Int\n}\nlet p = P(x: 1)\nprint(p.x)\nprint(p)" in
  Alcotest.(check bool) "print of a struct refused" true
    (has "cannot print a value of type 'P' (only Int, Double, Bool and String)" d)

let test_subset_eq_struct () =
  let _, d = front "struct P {\n  var x: Int\n}\nprint(P(x: 1) == P(x: 2))" in
  Alcotest.(check bool) "== on two structs refused" true
    (has "binary operator '==' cannot be applied to two 'P' operands" d)

let test_subset_let_field () =
  let _, d = front "struct C {\n  let k: Int\n  var n: Int\n}\nvar c = C(k: 1, n: 2)\nc.n = 5\nc.k = 5" in
  Alcotest.(check bool) "a `let` field is frozen" true (has "cannot assign to property: 'k' is a 'let' constant" d)

let test_subset_field_wrap () =
  (* `h.p = A()` must wrap into the FIELD's `any P` type, not store the struct raw *)
  let m =
    lower
      "protocol P { func v() -> Int }\nstruct A: P { func v() -> Int { return 1 } }\n\
       struct H { var p: P }\nvar h = H(p: A())\nh.p = A()\nprint(h.p.v())"
  in
  Alcotest.(check int) "both the init and the write wrap" 2 (wraps m)

let () =
  Alcotest.run "protocols"
    [
      ( "conformance",
        [
          Alcotest.test_case "accepts a conformer" `Quick test_conformance_ok;
          Alcotest.test_case "missing method" `Quick test_conformance_missing;
          Alcotest.test_case "wrong return type" `Quick test_conformance_wrong_sig;
          Alcotest.test_case "wrong parameter type" `Quick test_conformance_wrong_param;
          Alcotest.test_case "order and extras are fine" `Quick test_conformance_extra_ok;
          Alcotest.test_case "checked per protocol" `Quick test_conformance_two_protos;
          Alcotest.test_case "coercion uses the predicate" `Quick test_coercion_uses_predicate;
          Alcotest.test_case "print of any P refused" `Quick test_subset_print;
        ] );
      ( "tables 21c",
        [
          Alcotest.test_case "one per conformance" `Quick test_witness_tables;
          Alcotest.test_case "slots in requirement order" `Quick test_table_slot_order;
          Alcotest.test_case "no clause, no table" `Quick test_table_only_on_clause;
        ] );
      ( "wrap 21a",
        [
          Alcotest.test_case "one per concrete coercion" `Quick test_wrap_once_per_concrete;
          Alcotest.test_case "any P to any P is a move" `Quick test_wrap_skips_existential;
          Alcotest.test_case "P? wraps the payload" `Quick test_wrap_optional_payload;
          Alcotest.test_case "a field write wraps too" `Quick test_subset_field_wrap;
        ] );
      ( "dispatch 21b",
        [
          Alcotest.test_case "existential goes dynamic" `Quick test_dispatch_dynamic;
          Alcotest.test_case "concrete stays static" `Quick test_dispatch_static;
          Alcotest.test_case "slot is the requirement" `Quick test_dispatch_slot;
        ] );
      ( "optimizer",
        [
          Alcotest.test_case "-O keeps tables valid" `Quick test_optimizer_safe;
          Alcotest.test_case "-O keeps types apart" `Quick test_optimizer_keeps_types;
        ] );
      ( "subset",
        [
          Alcotest.test_case "print of a struct refused" `Quick test_subset_print_struct;
          Alcotest.test_case "== on two structs refused" `Quick test_subset_eq_struct;
          Alcotest.test_case "let field is frozen" `Quick test_subset_let_field;
        ] );
    ]
