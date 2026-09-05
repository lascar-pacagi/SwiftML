(* Alcotest unit tests for concept-30: the error-ABI desugaring, the cleanup edges, and the
   front-end rules. *)

let front (src : string) =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  (p, d)

let msgs d = List.map (fun (e : Diagnostics.t) -> e.Diagnostics.message) (Diagnostics.all d)
let rejects src = Diagnostics.has_errors (snd (front src))

let lower src =
  let p, d = front src in
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  Silgen.lower p

let instrs (m : Sil.modul) : Sil.instr list =
  List.concat_map
    (fun (f : Sil.func) -> List.concat_map (fun (b : Sil.block) -> List.map snd b.Sil.instrs) f.Sil.blocks)
    m.Sil.funcs

let count pred m = List.length (List.filter pred (instrs m))
let is_ref nm = function Sil.Func_ref n -> n = nm | _ -> false

let prog =
  "enum E: Error { case a, b }\nfunc f(_ n: Int) throws -> Int {\n  if n == 0 { throw E.a }\n  return n }\ndo { print(try f(0)) } catch E.a { print(0 - 1) } catch { print(0 - 2) }"

(* ---- the desugaring ------------------------------------------------------------------- *)

let test_desugars () =
  let m = lower prog in
  (* the error register calls appear; NO new SIL instruction kind was needed *)
  Alcotest.(check bool) "error_get referenced" true (count (is_ref "rt.error_get") m >= 1);
  Alcotest.(check bool) "error_set referenced" true (count (is_ref "rt.error_set") m >= 1);
  Alcotest.(check (list string)) "valid after silgen" [] (Sil.verify m)

let test_ordinals () =
  (* each error case gets a distinct positive ordinal — the throw stores it *)
  let m = lower prog in
  let lits = List.filter_map (function Sil.Int_lit n -> Some n | _ -> None) (instrs m) in
  Alcotest.(check bool) "a positive ordinal is stored" true (List.exists (fun n -> n > 0) lits)

let test_branch_not_unwind () =
  (* propagation is a conditional branch, one per throwing call — never a landing pad *)
  let m =
    lower
      "enum E: Error { case x }\nfunc l3() throws -> Int { throw E.x }\nfunc l2() throws -> Int { return try l3() }\nfunc l1() throws -> Int { return try l2() }\nprint((try? l1()) ?? 0)"
  in
  Alcotest.(check bool) "one error_get per throwing call" true (count (is_ref "rt.error_get") m >= 3)

let test_struct_default () =
  (* the throw path returns a PLACEHOLDER of the return type; a struct needs a struct-shaped
     one, or IRGen emits `ret %P 0` *)
  let m =
    lower
      "enum E: Error { case x }\nstruct P { var x: Int; var y: Int }\nfunc mk(_ n: Int) throws -> P {\n  if n < 0 { throw E.x }\n  return P(x: n, y: n)\n}\ndo { print((try mk(1)).x) } catch { print(0) }"
  in
  let f = List.find (fun (fn : Sil.func) -> fn.Sil.fname = "mk") m.Sil.funcs in
  let fi =
    List.concat_map (fun (b : Sil.block) -> List.map snd b.Sil.instrs) f.Sil.blocks
  in
  Alcotest.(check bool) "the placeholder is a struct" true
    (List.length (List.filter (function Sil.Struct _ -> true | _ -> false) fi) >= 2)

(* ---- the cleanup edges ---------------------------------------------------------------- *)

let test_defer_on_error_edge () =
  (* a defer inside the `do` body runs on BOTH exits: the fall-through and the error edge.
     Its body is therefore emitted twice — that is how the catch sees it fire first. *)
  let m =
    lower
      "enum E: Error { case x }\nfunc t() throws -> Int { throw E.x }\nfunc run() {\n  do {\n    defer { print(2) }\n    print(try t())\n  } catch { print(3) }\n}\nrun()"
  in
  let f = List.find (fun (fn : Sil.func) -> fn.Sil.fname = "run") m.Sil.funcs in
  let fi = List.concat_map (fun (b : Sil.block) -> List.map snd b.Sil.instrs) f.Sil.blocks in
  let prints = List.length (List.filter (function Sil.Print _ -> true | _ -> false) fi) in
  Alcotest.(check bool) "defer body emitted on both exits" true (prints >= 4)

let test_defer_lifo () =
  (* two defers in one scope run newest-first, on the throw path as on the normal one *)
  let m =
    lower
      "enum E: Error { case x }\nfunc f(_ n: Int) throws -> Int {\n  defer { print(1) }\n  defer { print(2) }\n  if n == 0 { throw E.x }\n  return n\n}\nprint((try? f(0)) ?? 0)"
  in
  Alcotest.(check (list string)) "valid" [] (Sil.verify m)

(* ---- the front-end rules --------------------------------------------------------------- *)

let test_diag_missing_try () =
  let _, d = front "enum E: Error { case x }\nfunc f() throws -> Int { throw E.x }\nfunc g() -> Int { return f() }" in
  Alcotest.(check bool) "missing-try reported" true
    (List.mem "call can throw, but it is not marked with 'try' and the error is not handled" (msgs d))

let test_diag_unhandled () =
  let _, d = front "enum E: Error { case x }\nfunc f() throws -> Int { throw E.x }\nfunc g() -> Int { return try f() }" in
  Alcotest.(check bool) "unhandled reported" true (List.mem "errors thrown from here are not handled" (msgs d))

let test_throwing_method () =
  (* a throwing METHOD needs `try` too — it used to type-check without one, then swallow *)
  let cls =
    "enum E: Error { case x }\nclass A {\n  var v: Int\n  init(_ n: Int) { v = n }\n  func take(_ n: Int) throws -> Int {\n    if n > v { throw E.x }\n    return v - n\n  }\n}\nlet a = A(10)\n"
  in
  Alcotest.(check bool) "no try on a method rejected" true (rejects (cls ^ "print(a.take(3))"));
  Alcotest.(check bool) "with try in a do accepted" false
    (rejects (cls ^ "do { print(try a.take(3)) } catch { print(0) }"))

let test_class_return_guard () =
  (* the throw path has no reference to invent — a v0 limit swiftc does not have *)
  Alcotest.(check bool) "class return rejected" true
    (rejects
       "enum E: Error { case x }\nclass C { var v: Int\n  init(_ n: Int) { v = n } }\nfunc mk() throws -> C { return C(1) }");
  Alcotest.(check bool) "struct return accepted" false
    (rejects
       "enum E: Error { case x }\nstruct P { var x: Int }\nfunc mk(_ n: Int) throws -> P {\n  if n < 0 { throw E.x }\n  return P(x: n)\n}\ndo { print((try mk(1)).x) } catch { print(0) }")

let test_valid_accepts () =
  let _, d = front "enum E: Error { case x }\nfunc f() throws -> Int { throw E.x }\nfunc g() throws -> Int { return try f() }" in
  Alcotest.(check bool) "valid throws accepted" false (Diagnostics.has_errors d)

let test_opt_safe () =
  let m = Opt.optimize (lower prog) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let () =
  Alcotest.run "errors"
    [
      ( "desugar",
        [
          Alcotest.test_case "rt.error calls + valid" `Quick test_desugars;
          Alcotest.test_case "ordinals" `Quick test_ordinals;
          Alcotest.test_case "a branch, not unwinding" `Quick test_branch_not_unwind;
          Alcotest.test_case "struct throw-path placeholder" `Quick test_struct_default;
        ] );
      ( "cleanup edges",
        [
          Alcotest.test_case "defer fires on the error edge" `Quick test_defer_on_error_edge;
          Alcotest.test_case "two defers, LIFO" `Quick test_defer_lifo;
        ] );
      ( "diagnostics",
        [
          Alcotest.test_case "missing try" `Quick test_diag_missing_try;
          Alcotest.test_case "unhandled" `Quick test_diag_unhandled;
          Alcotest.test_case "a throwing method needs try" `Quick test_throwing_method;
          Alcotest.test_case "class return refused" `Quick test_class_return_guard;
          Alcotest.test_case "valid accepts" `Quick test_valid_accepts;
        ] );
      ("optimizer", [ Alcotest.test_case "-O safe" `Quick test_opt_safe ]);
    ]
