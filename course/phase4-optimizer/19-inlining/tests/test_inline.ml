(* Alcotest unit tests for concept-19: function inlining. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  Silgen.lower p

let names (m : Sil.modul) = List.map (fun (f : Sil.func) -> f.Sil.fname) m.Sil.funcs

let count_apply (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> match i with Sil.Apply _ -> true | _ -> false) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let test_inline_leaf () =
  let m = Opt.inline_module (lower "func sq(_ x: Int) -> Int { return x * x }\nprint(sq(5))") in
  Alcotest.(check int) "the call was inlined (no apply left)" 0 (count_apply m);
  Alcotest.(check bool) "the inlined-away function is removed" false (List.mem "sq" (names m))

let test_recursive_kept () =
  (* fib is not a single-block leaf (it calls itself) — it must NOT be inlined, and stays *)
  let m = Opt.inline_module (lower "func fib(_ n: Int) -> Int {\n  if n < 2 { return n }\n  return fib(n - 1) + fib(n - 2)\n}\nprint(fib(5))") in
  Alcotest.(check bool) "recursive function kept" true (List.mem "fib" (names m));
  Alcotest.(check bool) "its calls are not inlined" true (count_apply m >= 1)

let test_multiblock_kept () =
  (* a leaf with internal control flow (multi-block) is not inlined in v0 *)
  let m = Opt.inline_module (lower "func clamp(_ x: Int) -> Int { if x < 0 { return 0 } else { return x } }\nprint(clamp(-3))") in
  Alcotest.(check bool) "multi-block leaf kept" true (List.mem "clamp" (names m))

let test_valid_after () =
  let m =
    Opt.optimize
      (lower "func dbl(_ x: Int) -> Int { return x + x }\nvar s = 0\nfor i in 0 ..< 4 { s = s + dbl(i) }\nprint(s)")
  in
  Alcotest.(check (list string)) "verifies after inline + the full pipeline" [] (Sil.verify m)

let () =
  Alcotest.run "inline"
    [
      ("inline", [ Alcotest.test_case "single-block leaf inlined + removed" `Quick test_inline_leaf ]);
      ("skip", [ Alcotest.test_case "recursive kept" `Quick test_recursive_kept;
                Alcotest.test_case "multi-block leaf kept" `Quick test_multiblock_kept ]);
      ("safety", [ Alcotest.test_case "valid after full -O" `Quick test_valid_after ]);
    ]
