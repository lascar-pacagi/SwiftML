(* Alcotest unit tests for concept-08 SILGen: the shape of the lowered SIL. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Silgen.lower p

let func_named (m : Sil.modul) name = List.find (fun (f : Sil.func) -> f.Sil.fname = name) m.Sil.funcs
let nblocks (f : Sil.func) = List.length f.Sil.blocks

let test_verify_ok () =
  Alcotest.(check (list string)) "valid program verifies clean" []
    (Sil.verify (lower "var n = 0\nwhile n < 3 { n = n + 1 }\nprint(n)"))

let test_main () =
  let m = lower "print(1)" in
  Alcotest.(check bool) "top-level statements form @main" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "main") m.Sil.funcs)

let test_func () =
  let m = lower "func add(_ a: Int, _ b: Int) -> Int { return a + b }\nprint(add(1, 2))" in
  let f = func_named m "add" in
  Alcotest.(check int) "add has 2 params" 2 (List.length f.Sil.params);
  Alcotest.(check bool) "add returns Int" true (f.Sil.ret = Types.TInt)

(* a binding lowers to alloc_stack + store; a use to a load (memory-based, no SSA) *)
let has_instr (f : Sil.func) (pred : Sil.instr -> bool) =
  List.exists (fun (b : Sil.block) -> List.exists (fun (_, i) -> pred i) b.Sil.instrs) f.Sil.blocks

let test_memory_model () =
  let main = func_named (lower "let x = 1\nprint(x)") "main" in
  Alcotest.(check bool) "alloc_stack for the binding" true
    (has_instr main (function Sil.Alloc_stack _ -> true | _ -> false));
  Alcotest.(check bool) "store the initializer" true
    (has_instr main (function Sil.Store _ -> true | _ -> false));
  Alcotest.(check bool) "load on use" true (has_instr main (function Sil.Load _ -> true | _ -> false))

let test_if_cfg () =
  let main = func_named (lower "let x = 1\nif x < 0 { print(x) } else { print(0) }") "main" in
  Alcotest.(check bool) "if builds >= 4 blocks (entry/then/else/merge)" true (nblocks main >= 4);
  Alcotest.(check bool) "and a cond_br" true
    (List.exists (fun (b : Sil.block) -> match b.Sil.term with Sil.Cond_br _ -> true | _ -> false) main.Sil.blocks)

let test_while_backedge () =
  let main = func_named (lower "var n = 0\nwhile n < 3 { n = n + 1 }") "main" in
  (* a loop has a back-edge: a block branches to an earlier block id *)
  let backedge =
    List.exists (fun (b : Sil.block) -> match b.Sil.term with Sil.Br t -> t < b.Sil.bid | _ -> false) main.Sil.blocks
  in
  Alcotest.(check bool) "while has a back-edge" true backedge

let () =
  Alcotest.run "silgen"
    [
      ("verify", [ Alcotest.test_case "verifier accepts valid SIL" `Quick test_verify_ok ]);
      ("structure", [ Alcotest.test_case "main + functions" `Quick test_main; Alcotest.test_case "function lowering" `Quick test_func ]);
      ("memory", [ Alcotest.test_case "alloc_stack/load/store" `Quick test_memory_model ]);
      ("cfg", [ Alcotest.test_case "if builds a diamond" `Quick test_if_cfg; Alcotest.test_case "while has a back-edge" `Quick test_while_backedge ]);
    ]
