(* Alcotest unit tests for concept-19: function inlining — the first inter-procedural pass.
   Grouped into the transform, what `inlinable` refuses, and safety. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Silgen.lower p

let names (m : Sil.modul) = List.map (fun (f : Sil.func) -> f.Sil.fname) m.Sil.funcs

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let is_apply = function Sil.Apply _ -> true | _ -> false
let is_mul = function Sil.Binop (Ast.Mul, _, _) -> true | _ -> false
let count_apply = count_instr is_apply

(* every value an instruction defines must have a type in its function's table — the splice has
   to carry the callee's val_ty across, and this is where forgetting shows up *)
let all_typed (m : Sil.modul) : bool =
  List.for_all
    (fun (f : Sil.func) ->
      List.for_all
        (fun (b : Sil.block) ->
          List.for_all (fun (v, i) -> match i with Sil.Store _ -> true | _ -> ignore i; Hashtbl.mem f.Sil.val_ty v) b.Sil.instrs)
        f.Sil.blocks)
    m.Sil.funcs

(* ---- the transform ---- *)

let test_inline_leaf () =
  let before = lower "func sq(_ x: Int) -> Int { return x * x }\nprint(sq(5))" in
  Alcotest.(check int) "raw has the call" 1 (count_apply before);
  let m = Opt.inline_module (lower "func sq(_ x: Int) -> Int { return x * x }\nprint(sq(5))") in
  Alcotest.(check int) "the call was inlined (no apply left)" 0 (count_apply m);
  Alcotest.(check bool) "the inlined-away function is removed" false (List.mem "sq" (names m));
  Alcotest.(check bool) "the body came with it" true (count_instr is_mul m >= 1)

let test_args_in_order () =
  (* the second parameter must map to the second argument: a - b, not b - a *)
  let m = Opt.inline_module (lower "func minus(_ a: Int, _ b: Int) -> Int { return a - b }\nprint(minus(10, 3))") in
  Alcotest.(check int) "no call left" 0 (count_apply m);
  (* inlining runs on raw SIL, so the arguments land in the callee's slots: promote first, then
     fold, and the direction of the subtraction is what the literal says *)
  let m' = Opt.run_pipeline [ { Opt.name = "m2r"; run = Opt.mem2reg }; { Opt.name = "cf"; run = Opt.constant_fold } ] m in
  let has n = count_instr (function Sil.Int_lit x -> x = n | _ -> false) m' >= 1 in
  Alcotest.(check bool) "folds to 7, not -7" true (has 7);
  Alcotest.(check bool) "and -7 is nowhere" false (has (-7))

let test_types_carried () =
  let m = Opt.inline_module (lower "struct P { var x: Int\n  var y: Int }\nfunc mk(_ n: Int) -> P { return P(x: n, y: n * 2) }\nlet p = mk(4)\nprint(p.x + p.y)") in
  Alcotest.(check int) "no call left" 0 (count_apply m);
  Alcotest.(check bool) "every spliced value has a type" true (all_typed m);
  Alcotest.(check (list string)) "and it verifies" [] (Sil.verify m)

let test_two_sites_and_rounds () =
  (* both call sites get a copy, and a call whose argument is a call needs a second round *)
  let m = Opt.inline_module (lower "func sq(_ x: Int) -> Int { return x * x }\nfunc f(_ n: Int) -> Int { return sq(n) + sq(n + 1) }\nprint(f(3))") in
  Alcotest.(check int) "nothing calls anything" 0 (count_apply m);
  Alcotest.(check bool) "two copies of the body" true (count_instr is_mul m >= 2);
  let n = Opt.inline_module (lower "func add(_ a: Int, _ b: Int) -> Int { return a + b }\nfunc mul(_ a: Int, _ b: Int) -> Int { return a * b }\nprint(add(mul(3, 4), mul(5, 6)))") in
  Alcotest.(check (list string)) "only main is left" [ "main" ] (names n)

(* ---- what `inlinable` refuses ---- *)

let test_recursive_kept () =
  (* fib is not a single-block leaf (it calls itself) — it must NOT be inlined, and stays; the
     leaf beside it must still go, so a pass that inlines nothing fails this case *)
  let m = Opt.inline_module (lower "func sq(_ x: Int) -> Int { return x * x }\nfunc fib(_ n: Int) -> Int {\n  if n < 2 { return n }\n  return fib(n - 1) + fib(n - 2)\n}\nprint(fib(5) + sq(3))") in
  Alcotest.(check bool) "recursive function kept" true (List.mem "fib" (names m));
  Alcotest.(check bool) "the leaf beside it went" false (List.mem "sq" (names m));
  Alcotest.(check bool) "its calls are not inlined" true (count_apply m >= 1)

let test_multiblock_kept () =
  (* a leaf with internal control flow (multi-block) is not inlined in v0 *)
  let m = Opt.inline_module (lower "func clamp(_ x: Int) -> Int { if x < 0 { return 0 } else { return x } }\nfunc sq(_ x: Int) -> Int { return x * x }\nprint(clamp(-3) + sq(2))") in
  Alcotest.(check bool) "multi-block leaf kept" true (List.mem "clamp" (names m));
  Alcotest.(check bool) "single-block leaf gone" false (List.mem "sq" (names m))

let test_mutual_recursion_kept () =
  let m = Opt.inline_module (lower "func isEven(_ n: Int) -> Bool {\n  if n == 0 { return true }\n  return isOdd(n - 1)\n}\nfunc isOdd(_ n: Int) -> Bool {\n  if n == 0 { return false }\n  return isEven(n - 1)\n}\nfunc sq(_ x: Int) -> Int { return x * x }\nprint(isEven(4) == (sq(2) > 3))") in
  Alcotest.(check bool) "isEven kept" true (List.mem "isEven" (names m));
  Alcotest.(check bool) "isOdd kept" true (List.mem "isOdd" (names m));
  Alcotest.(check bool) "the leaf beside them went" false (List.mem "sq" (names m))

let test_still_called_kept () =
  (* sq is inlined into sumSq and dropped; sumSq is still called by main and is not *)
  let m = Opt.inline_module (lower "func sq(_ x: Int) -> Int { return x * x }\nfunc sumSq(_ n: Int) -> Int {\n  var s = 0\n  var i = 0\n  while i < n { s = s + sq(i)\n    i = i + 1 }\n  return s\n}\nprint(sumSq(5))") in
  Alcotest.(check bool) "the still-called function is kept" true (List.mem "sumSq" (names m));
  Alcotest.(check bool) "the inlined-away one is not" false (List.mem "sq" (names m));
  Alcotest.(check int) "one call left: main -> sumSq" 1 (count_apply m)

(* ---- safety ---- *)

let test_valid_after () =
  (* a positive claim first, so a pass that inlines nothing cannot pass this case *)
  Alcotest.(check int) "the leaf really was inlined under -O" 0
    (count_apply (Opt.optimize (lower "func dbl(_ x: Int) -> Int { return x + x }\nprint(dbl(4))")));
  List.iter
    (fun src ->
      let m = Opt.optimize (lower src) in
      Alcotest.(check (list string)) "verifies after inline + the full pipeline" [] (Sil.verify m);
      Alcotest.(check bool) "every value typed" true (all_typed m))
    [
      "func dbl(_ x: Int) -> Int { return x + x }\nvar s = 0\nfor i in 0 ..< 4 { s = s + dbl(i) }\nprint(s)";
      "func fib(_ n: Int) -> Int {\n  if n < 2 { return n }\n  return fib(n - 1) + fib(n - 2)\n}\nprint(fib(10))";
      "struct P { var x: Int\n  var y: Int }\nfunc mk(_ n: Int) -> P { return P(x: n, y: n * 2) }\nprint(mk(4).x)";
    ]

let () =
  Alcotest.run "inline"
    [
      ( "the splice (TODO 19)",
        [
          Alcotest.test_case "leaf inlined, callee removed" `Quick test_inline_leaf;
          Alcotest.test_case "arguments bind in order" `Quick test_args_in_order;
          Alcotest.test_case "value types travel with it" `Quick test_types_carried;
          Alcotest.test_case "both sites; a second round" `Quick test_two_sites_and_rounds;
        ] );
      ( "what stays (given: inlinable)",
        [
          Alcotest.test_case "recursive kept, leaf goes" `Quick test_recursive_kept;
          Alcotest.test_case "multi-block leaf kept" `Quick test_multiblock_kept;
          Alcotest.test_case "mutual recursion kept" `Quick test_mutual_recursion_kept;
          Alcotest.test_case "still-called function kept" `Quick test_still_called_kept;
        ] );
      ("safety", [ Alcotest.test_case "valid after full -O" `Quick test_valid_after ]);
    ]
