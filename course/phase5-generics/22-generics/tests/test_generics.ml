(* Alcotest unit tests for concept 22 — generic functions: call-site inference and the erased
   lowering. One group per TODO hole: `inference` needs only `TODO(22-sema)`, `lowering` needs
   both, and `body` covers the GIVEN rules that are checked inside a generic function without
   any call, so that group is green from the start. *)

let front (src : string) : Ast.program * Diagnostics.sink =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  (p, d)

let msgs (d : Diagnostics.sink) : string list =
  List.rev_map (fun (e : Diagnostics.t) -> e.Diagnostics.message) d.Diagnostics.diags

let has m d = List.mem m (msgs d)

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
let opens = count_instr (function Sil.Open_existential _ -> true | _ -> false)

let proto = "protocol P { func v() -> Int }\nstruct A: P { var x: Int\n  func v() -> Int { return x } }\n"
let two = proto ^ "struct B: P { func v() -> Int { return 2 } }\n"

(* ---------------------------------------------------------------- TODO(22-sema) *)

let test_inference () =
  (* the result of a `-> T` call is the CONCRETE binding: `.x` is A's, not any P's *)
  let _, d = front (proto ^ "func id<T: P>(_ t: T) -> T { return t }\nlet a = id(A(x: 1))\nprint(a.x)") in
  Alcotest.(check (list string)) "T result usable concretely" [] (msgs d)

let test_conflict () =
  let _, d = front (two ^ "func f<T: P>(_ a: T, _ b: T) -> Int { return 0 }\nprint(f(A(x: 1), B()))") in
  Alcotest.(check bool) "conflicting T rejected" true
    (has "conflicting arguments to generic parameter 'T' ('A' vs. 'B')" d)

let test_same_twice_ok () =
  let _, d = front (proto ^ "func f<T: P>(_ a: T, _ b: T) -> Int { return a.v() + b.v() }\nprint(f(A(x: 1), A(x: 2)))") in
  Alcotest.(check (list string)) "two arguments of one type agree" [] (msgs d)

let test_constraint () =
  let _, d =
    front "protocol P { func v() -> Int }\nstruct C { var y: Int }\nfunc f<T: P>(_ a: T) -> Int { return a.v() }\nprint(f(C(y: 1)))"
  in
  Alcotest.(check bool) "non-conformer rejected" true (has "global function 'f' requires that 'C' conform to 'P'" d)

let test_constraint_scalar () =
  let _, d = front "protocol P { func v() -> Int }\nfunc f<T: P>(_ a: T) -> Int { return a.v() }\nprint(f(3))" in
  Alcotest.(check bool) "an Int cannot be T either" true (has "global function 'f' requires that 'Int' conform to 'P'" d)

let test_non_t_param_checked () =
  (* a parameter that is not in a T position is checked the ordinary way *)
  let _, d = front (proto ^ "func f<T: P>(_ a: T, _ k: Int) -> Int { return a.v() * k }\nprint(f(A(x: 1), true))") in
  Alcotest.(check bool) "Bool where Int expected" true
    (has "cannot convert value of type 'Bool' to specified type 'Int'" d)

let test_arity () =
  let _, d = front (proto ^ "func f<T: P>(_ a: T) -> Int { return a.v() }\nprint(f(A(x: 1), A(x: 2)))") in
  Alcotest.(check bool) "arity before inference" true (has "function 'f' expects 1 argument(s) but 2 given" d)

let test_generic_from_generic () =
  let _, d =
    front (proto ^ "func inner<T: P>(_ t: T) -> Int { return t.v() }\nfunc outer<T: P>(_ t: T) -> Int { return inner(t) + 1 }\nprint(outer(A(x: 1)))")
  in
  Alcotest.(check (list string)) "T binds to the caller's T" [] (msgs d)

(* ---------------------------------------------------------------- TODO(22-silgen) *)

let test_erased_lowering () =
  let m = lower (proto ^ "func id<T: P>(_ t: T) -> T { return t }\nlet a = id(A(x: 1))\nprint(a.v())") in
  Alcotest.(check int) "one wrap at the call" 1 (wraps m);
  Alcotest.(check int) "one open of the T result" 1 (opens m);
  Alcotest.(check (list string)) "module verifies" [] (Sil.verify m)

let test_one_copy () =
  (* erasure, not specialization: two argument types, still ONE @id *)
  let m = lower (two ^ "func id<T: P>(_ t: T) -> T { return t }\nprint(id(A(x: 1)).v() + id(B()).v())") in
  Alcotest.(check int) "one copy of the generic" 1
    (List.length (List.filter (fun (f : Sil.func) -> f.Sil.fname = "id") m.Sil.funcs));
  Alcotest.(check int) "two wraps, two opens" 2 (wraps m);
  Alcotest.(check int) "two opens" 2 (opens m)

let test_no_open_when_not_t () =
  let m = lower (proto ^ "func k<T: P>(_ t: T) -> Int { return t.v() }\nprint(k(A(x: 1)))") in
  Alcotest.(check int) "an Int result is not erased" 0 (opens m)

let test_gg_stays_erased () =
  let m =
    lower (proto ^ "func inner<T: P>(_ t: T) -> Int { return t.v() }\nfunc outer<T: P>(_ t: T) -> Int { return inner(t) + 1 }\nprint(outer(A(x: 1)))")
  in
  Alcotest.(check int) "only the outer call wraps" 1 (wraps m);
  Alcotest.(check int) "nothing concrete to open" 0 (opens m)

let test_optimizer_safe () =
  let m = Opt.optimize (lower (proto ^ "func id<T: P>(_ t: T) -> T { return t }\nprint(id(A(x: 5)).v())")) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

(* ---------------------------------------------------------------- the given body rules *)

let test_member_on_t () =
  let _, d =
    front "protocol P { func v() -> Int }\nstruct A: P { func v() -> Int { return 1 }\n  func w() -> Int { return 9 } }\nfunc f<T: P>(_ a: T) -> Int { return a.w() }"
  in
  Alcotest.(check bool) "T exposes only the constraint" true (has "value of type 'T' has no member 'w'" d)

let test_eq_on_t () =
  let _, d = front "protocol P { func v() -> Int }\nfunc f<T: P>(_ a: T, _ b: T) -> Bool { return a == b }" in
  Alcotest.(check bool) "== on two T refused" true (has "binary operator '==' cannot be applied to two 'T' operands" d)

let test_unconstrained_rejected () =
  let _, d = front "func f<T>(_ a: T) -> T { return a }\nprint(1)" in
  Alcotest.(check bool) "v0 requires a constraint" true
    (has "type parameter 'T' needs a protocol constraint in this subset (write '<T: SomeProtocol>')" d)

let () =
  Alcotest.run "generics"
    [
      ( "inference",
        [
          Alcotest.test_case "binds + substitutes" `Quick test_inference;
          Alcotest.test_case "same type twice is fine" `Quick test_same_twice_ok;
          Alcotest.test_case "conflicting T" `Quick test_conflict;
          Alcotest.test_case "constraint violation" `Quick test_constraint;
          Alcotest.test_case "a scalar cannot be T" `Quick test_constraint_scalar;
          Alcotest.test_case "non-T parameter checked" `Quick test_non_t_param_checked;
          Alcotest.test_case "arity first" `Quick test_arity;
          Alcotest.test_case "generic from generic" `Quick test_generic_from_generic;
        ] );
      ( "lowering",
        [
          Alcotest.test_case "erased once, wrap + open" `Quick test_erased_lowering;
          Alcotest.test_case "two types, one copy" `Quick test_one_copy;
          Alcotest.test_case "no open for an Int result" `Quick test_no_open_when_not_t;
          Alcotest.test_case "generic from generic erased" `Quick test_gg_stays_erased;
          Alcotest.test_case "-O keeps it valid" `Quick test_optimizer_safe;
        ] );
      ( "body",
        [
          Alcotest.test_case "member not on T" `Quick test_member_on_t;
          Alcotest.test_case "== on two T" `Quick test_eq_on_t;
          Alcotest.test_case "unconstrained T rejected" `Quick test_unconstrained_rejected;
        ] );
    ]
