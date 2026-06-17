(* Alcotest unit tests for concept-30: the error-ABI desugaring + diagnostics. *)
let front (src : string) =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d; (p, d)
let msgs d = List.rev_map (fun (e : Diagnostics.t) -> e.Diagnostics.message) d.Diagnostics.diags
let lower s = let p, d = front s in
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d); Silgen.lower p
let count pred m = List.fold_left (fun a (f:Sil.func) -> List.fold_left (fun a (b:Sil.block) -> a + List.length (List.filter (fun (_,i)->pred i) b.Sil.instrs)) a f.Sil.blocks) 0 m.Sil.funcs
let is_app_of nm = function Sil.Func_ref n -> n = nm | _ -> false
let prog = "enum E: Error { case a, b }\nfunc f(_ n: Int) throws -> Int {\n  if n == 0 { throw E.a }\n  return n }\ndo { print(try f(0)) } catch E.a { print(-1) } catch { print(-2) }"

let test_desugars () =
  let m = lower prog in
  (* the error register calls appear; NO new SIL instruction kinds were needed *)
  Alcotest.(check bool) "error_get referenced" true (count (is_app_of "rt.error_get") m >= 1);
  Alcotest.(check bool) "error_set referenced" true (count (is_app_of "rt.error_set") m >= 1);
  Alcotest.(check (list string)) "valid after silgen" [] (Sil.verify m)

let test_ordinals () =
  (* each error case gets a distinct positive ordinal — the throw stores it *)
  let m = lower prog in
  let lits = List.fold_left (fun acc (f:Sil.func) -> List.fold_left (fun acc (b:Sil.block) -> List.fold_left (fun acc (_,i) -> match i with Sil.Int_lit n -> n::acc | _ -> acc) acc b.Sil.instrs) acc f.Sil.blocks) [] m.Sil.funcs in
  Alcotest.(check bool) "a positive ordinal is stored" true (List.exists (fun n -> n > 0) lits)

let test_diag_missing_try () =
  let _, d = front "enum E: Error { case x }\nfunc f() throws -> Int { throw E.x }\nfunc g() -> Int { return f() }" in
  Alcotest.(check bool) "missing-try reported" true
    (List.mem "call can throw, but it is not marked with 'try' and the error is not handled" (msgs d))

let test_diag_unhandled () =
  let _, d = front "enum E: Error { case x }\nfunc f() throws -> Int { throw E.x }\nfunc g() -> Int { return try f() }" in
  Alcotest.(check bool) "unhandled reported" true (List.mem "errors thrown from here are not handled" (msgs d))

let test_valid_accepts () =
  let _, d = front "enum E: Error { case x }\nfunc f() throws -> Int { throw E.x }\nfunc g() throws -> Int { return try f() }" in
  Alcotest.(check bool) "valid throws accepted" false (Diagnostics.has_errors d)

let test_opt_safe () =
  let m = Opt.optimize (lower prog) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let () = Alcotest.run "errors" [
  ("desugar", [ Alcotest.test_case "rt.error calls + valid" `Quick test_desugars; Alcotest.test_case "ordinals" `Quick test_ordinals ]);
  ("diagnostics", [ Alcotest.test_case "missing try" `Quick test_diag_missing_try; Alcotest.test_case "unhandled" `Quick test_diag_unhandled; Alcotest.test_case "valid accepts" `Quick test_valid_accepts ]);
  ("optimizer", [ Alcotest.test_case "-O safe" `Quick test_opt_safe ]); ]
