(* Alcotest unit tests for concept-28: copy propagation + WMO devirtualization. *)

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

let is_copy = function Sil.Copy_value _ -> true | _ -> false
let is_destroy = function Sil.Destroy_value _ -> true | _ -> false

let tracer = "class T { var id: Int\n  init(_ i: Int) { id = i } }\n"

let test_param_copy_removed () =
  let m = Opt.optimize (lower (tracer ^ "func f(_ a: T) -> Int {\n  let c = a\n  return c.id\n}\nprint(f(T(5)))")) in
  Alcotest.(check int) "no copies survive" 0 (count_instr is_copy m)

let test_chain_removed () =
  let m = Opt.optimize (lower (tracer ^ "func g(_ n: T) -> Int {\n  let a = n\n  let b = a\n  return b.id\n}\nprint(g(T(2)))")) in
  Alcotest.(check int) "chained copies all gone" 0 (count_instr is_copy m)

let test_owned_local_pair_removed () =
  (* `let a = T(1); let c = a` — the copy's destroy precedes a's: removable *)
  let m = Opt.optimize (lower (tracer ^ "func f() -> Int {\n  let a = T(1)\n  let c = a\n  return c.id\n}\nprint(f())")) in
  Alcotest.(check int) "borrow-of-local pair gone" 0 (count_instr is_copy m)

let test_escaping_copy_kept () =
  (* the copy is RETURNED (consumed by return, not destroy): the PASS must keep it — it
     transfers ownership to the caller. (The full -O pipeline may still erase it after
     INLINING exposes both ends of the transfer in one function — that composition is sound,
     which is why this test runs the pass alone.) *)
  let m =
    Opt.run_pipeline
      [ { Opt.name = "mem2reg"; run = Opt.mem2reg }; { Opt.name = "cp"; run = Opt.copy_propagation } ]
      (lower (tracer ^ "func f(_ a: T) -> T {\n  return a\n}\nprint(f(T(7)).id)"))
  in
  Alcotest.(check bool) "the ownership-transferring copy survives the pass" true (count_instr is_copy m >= 1)

let test_balanced_traffic () =
  (* whatever remains must stay balanced: in this leak-free program every remaining copy has
     a destroy partner somewhere (allocs add the rest) *)
  let m = Opt.optimize (lower (tracer ^ "func f(_ a: T) -> Int {\n  let c = a\n  return c.id\n}\nprint(f(T(5)))")) in
  let allocs = count_instr (function Sil.Alloc_ref _ -> true | _ -> false) m in
  Alcotest.(check int) "destroys = copies + allocs" (count_instr is_copy m + allocs) (count_instr is_destroy m)

let () =
  Alcotest.run "arcopt"
    [
      ("removal", [ Alcotest.test_case "param borrow-copy" `Quick test_param_copy_removed;
                    Alcotest.test_case "chained copies" `Quick test_chain_removed;
                    Alcotest.test_case "owned-local pair" `Quick test_owned_local_pair_removed ]);
      ("safety", [ Alcotest.test_case "escaping copy kept" `Quick test_escaping_copy_kept;
                   Alcotest.test_case "traffic stays balanced" `Quick test_balanced_traffic ]);
    ]
