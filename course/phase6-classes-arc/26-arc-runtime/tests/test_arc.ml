(* Alcotest for concept 26. The holes separate: `ownership 26a` and `destroy 26b` read the SIL
   Silgen produced, `runtime 26c` reads the emitted LLVM. *)

let front (src : string) : Ast.program * Diagnostics.sink =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  (p, d)

let msgs (d : Diagnostics.sink) : string list =
  List.rev_map (fun (e : Diagnostics.t) -> e.Diagnostics.message) d.Diagnostics.diags

let lower (src : string) : Sil.modul =
  let p, d = front src in
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  Silgen.lower p

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

(* a function's instructions in PROGRAM order — a block accumulates them with `::`, so what
   is stored is the reverse of what `--emit-sil` prints *)
let body (m : Sil.modul) (name : string) : Sil.instr list =
  match List.find_opt (fun (f : Sil.func) -> f.Sil.fname = name) m.Sil.funcs with
  | Some f -> List.concat_map (fun (b : Sil.block) -> List.rev_map snd b.Sil.instrs) f.Sil.blocks
  | None -> []

let in_func (m : Sil.modul) (name : string) (pred : Sil.instr -> bool) : int =
  match List.find_opt (fun (f : Sil.func) -> f.Sil.fname = name) m.Sil.funcs with
  | Some _ -> List.length (List.filter pred (body m name))
  | None -> -1

let has (needle : string) (hay : string) : bool =
  let n = String.length needle and h = String.length hay in
  let rec go i = i + n <= h && (String.sub hay i n = needle || go (i + 1)) in
  n = 0 || go 0

let tracer = "class T { var id: Int\n  init(_ i: Int) { id = i }\n  deinit { print(id) } }\n"
let is_retain = function Sil.Retain _ -> true | _ -> false
let is_release = function Sil.Release _ -> true | _ -> false

(* ---- TODO(26a): take_ownership ---- *)

let test_fresh_consumed () =
  (* `let a = T(1)` consumes the constructor's +1 — no retain at all *)
  let m = lower (tracer ^ "func f() {\n  let a = T(1)\n  print(a.id)\n}\nf()") in
  Alcotest.(check int) "no retain for a consumed fresh value" 0 (in_func m "f" is_retain);
  Alcotest.(check int) "one release (scope end)" 1 (in_func m "f" is_release)

let test_borrow_retains () =
  (* `let c = a` borrows a slot's value: a retain must balance c's scope-end release *)
  let m = lower (tracer ^ "func f() {\n  let a = T(1)\n  let c = a\n  print(c.id)\n}\nf()") in
  Alcotest.(check int) "one retain in f (the borrow)" 1 (in_func m "f" is_retain);
  Alcotest.(check int) "two releases in f (both locals)" 2 (in_func m "f" is_release)

let test_param_is_borrowed () =
  (* an argument is GUARANTEED: the callee neither retains nor releases it *)
  let m = lower (tracer ^ "func use(_ t: T) -> Int { return t.id }\nfunc f() { let a = T(1)\n  print(use(a)) }\nf()") in
  Alcotest.(check int) "no retain in the callee" 0 (in_func m "use" is_retain);
  Alcotest.(check int) "no release in the callee" 0 (in_func m "use" is_release)

let test_return_transfers () =
  (* the caller receives +1: the local is retained BEFORE the scope releases it *)
  let m = lower (tracer ^ "func mk() -> T { let t = T(6)\n  return t }\nfunc g() { let t = mk()\n  print(t.id) }\ng()") in
  Alcotest.(check int) "mk retains before returning" 1 (in_func m "mk" is_retain);
  Alcotest.(check int) "mk still releases its local" 1 (in_func m "mk" is_release);
  Alcotest.(check int) "the caller consumes, not retains" 0 (in_func m "g" is_retain)

let test_reassign_order () =
  (* the OLD value is released AFTER the new one is stored: `v = v` must not free itself *)
  let m = lower (tracer ^ "func f() {\n  var v = T(1)\n  v = T(2)\n  print(v.id)\n}\nf()") in
  let rec after_store = function
    | Sil.Store _ :: rest -> List.exists is_release rest
    | _ :: rest -> after_store rest
    | [] -> false
  in
  Alcotest.(check bool) "release follows the store" true (after_store (body m "f"));
  Alcotest.(check int) "two releases (old value, then scope)" 2 (in_func m "f" is_release)

(* ---- TODO(26b): the destroy chain ---- *)

let hier =
  "class L { var id: Int\n  init(_ i: Int) { id = i } }\n\
   class A { var x: Int\n  init(_ v: Int) { x = v } }\n\
   class B: A { var l: L\n  init(_ v: Int, _ l0: L) { l = l0\n    super.init(v) } }\nprint(1)"

let refs (m : Sil.modul) (fname : string) (target : string) : bool =
  List.exists (function Sil.Func_ref n -> n = target | _ -> false) (body m fname)

let test_two_chains () =
  let m = lower hier in
  Alcotest.(check int) "B.destroy releases B's field" 1 (in_func m "B.destroy" is_release);
  Alcotest.(check int) "B.deinit releases nothing" 0 (in_func m "B.deinit" is_release);
  Alcotest.(check bool) "B.deinit chains to A.deinit" true (refs m "B.deinit" "A.deinit");
  Alcotest.(check bool) "B.destroy chains to A.destroy" true (refs m "B.destroy" "A.destroy")

let test_destroy_super_first () =
  (* the field chain runs BASE first: the super call precedes this class's own release *)
  let m = lower hier in
  let rec super_first = function
    | Sil.Func_ref "A.destroy" :: rest -> List.exists is_release rest
    | _ :: rest -> super_first rest
    | [] -> false
  in
  Alcotest.(check bool) "super.destroy before own release" true (super_first (body m "B.destroy"));
  Alcotest.(check int) "a base with no class field is empty" 0 (in_func m "A.destroy" is_release)

let test_destructor_synthesized () =
  let m = lower (tracer ^ "print(1)") in
  Alcotest.(check bool) "T.deinit exists" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "T.deinit") m.Sil.funcs);
  Alcotest.(check bool) "T.destroy exists too" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "T.destroy") m.Sil.funcs)

(* ---- TODO(26c): rt.release ---- *)

let test_rt_release () =
  let ll = Irgen.emit_llvm (lower (tracer ^ "func f() { let a = T(1)\n  print(a.id) }\nf()")) in
  Alcotest.(check bool) "it decrements" true (has "%n = sub i64 %rc, 1" ll);
  Alcotest.(check bool) "and tests for zero" true (has "icmp eq i64 %n, 0" ll);
  Alcotest.(check bool) "slot 0 then slot 1" true
    (has "%dtor = load ptr, ptr %vt" ll && has "getelementptr ptr, ptr %vt, i64 1" ll);
  Alcotest.(check bool) "then frees, once" true (has "call void @free(ptr %o)" ll);
  Alcotest.(check bool) "the two chains sit in the table" true
    (has "[ptr @T.deinit, ptr @T.destroy]" ll)

(* ---- the optimizer must not touch ARC traffic ---- *)

let test_optimizer_preserves () =
  let src = tracer ^ "func f() {\n  let a = T(1)\n  let c = a\n  print(c.id)\n}\nf()" in
  let raw = lower src in
  let before_r = count_instr is_retain raw and before_rel = count_instr is_release raw in
  let m = Opt.optimize (lower src) in
  Alcotest.(check int) "retain count unchanged by -O" before_r (count_instr is_retain m);
  Alcotest.(check int) "release count unchanged by -O" before_rel (count_instr is_release m);
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m);
  Alcotest.(check bool) "the destructors stay alive" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "T.destroy") m.Sil.funcs)

(* ---- the v0 guards (given code) ---- *)

let test_guards () =
  let _, d = front "class K { var x: Int\n  init() { x = 1 } }\nstruct S { var k: K }" in
  Alcotest.(check bool) "no class inside a struct" true
    (List.mem "class references inside structs are not supported in this subset" (msgs d));
  let _, d2 = front "class K { var x: Int\n  init(_ v: Int) { x = v } }\nfunc f() { let k: K? = K(1) }\nf()" in
  Alcotest.(check bool) "no class inside an optional" true
    (List.mem "optional class references are not supported in this subset" (msgs d2))

let () =
  Alcotest.run "arc"
    [
      ( "ownership 26a",
        [ Alcotest.test_case "a fresh +1 is consumed" `Quick test_fresh_consumed;
          Alcotest.test_case "a borrow is retained" `Quick test_borrow_retains;
          Alcotest.test_case "a param is guaranteed" `Quick test_param_is_borrowed;
          Alcotest.test_case "a return transfers +1" `Quick test_return_transfers;
          Alcotest.test_case "reassign: store, then free" `Quick test_reassign_order ] );
      ( "destroy 26b",
        [ Alcotest.test_case "the two chains" `Quick test_two_chains;
          Alcotest.test_case "fields die base-first" `Quick test_destroy_super_first;
          Alcotest.test_case "both are synthesized" `Quick test_destructor_synthesized ] );
      ("runtime 26c", [ Alcotest.test_case "rt.release, line by line" `Quick test_rt_release ]);
      ("optimizer", [ Alcotest.test_case "-O keeps every ARC op" `Quick test_optimizer_preserves ]);
      ("given rules", [ Alcotest.test_case "the v0 guards" `Quick test_guards ]);
    ]
