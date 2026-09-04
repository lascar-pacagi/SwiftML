(* Alcotest unit tests for concept-08 SILGen: the lowered module's structure, in-process, one
   group per TODO(08) hole. The cram files read the printed SIL; these read the data structure,
   so a case can ask a question the printer does not answer (which block a `br` names, whether a
   block is the loop's latch). Group "given" is the memory model, which is not a hole — it is
   green before you start and pins the vocabulary the holes must produce. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Silgen.lower p

let func_named (m : Sil.modul) name = List.find (fun (f : Sil.func) -> f.Sil.fname = name) m.Sil.funcs
let main_of src = func_named (lower src) "main"
let nblocks (f : Sil.func) = List.length f.Sil.blocks
let block (f : Sil.func) n = List.find (fun (b : Sil.block) -> b.Sil.bid = n) f.Sil.blocks

let has_instr (f : Sil.func) (pred : Sil.instr -> bool) =
  List.exists (fun (b : Sil.block) -> List.exists (fun (_, i) -> pred i) b.Sil.instrs) f.Sil.blocks

let count_instr (f : Sil.func) (pred : Sil.instr -> bool) =
  List.fold_left
    (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs))
    0 f.Sil.blocks

let is_alloc = function Sil.Alloc_stack _ -> true | _ -> false
let is_store = function Sil.Store _ -> true | _ -> false
let is_load = function Sil.Load _ -> true | _ -> false

(* the block a straight `br` leaves for; -1 if the block does not end in one *)
let br_target (b : Sil.block) = match b.Sil.term with Sil.Br n -> n | _ -> -1

(* every block whose terminator is an unconditional branch to [n] *)
let preds_by_br (f : Sil.func) n =
  List.filter (fun (b : Sil.block) -> br_target b = n) f.Sil.blocks |> List.map (fun b -> b.Sil.bid)

let cond_br_of (b : Sil.block) = match b.Sil.term with Sil.Cond_br (_, t, e) -> (t, e) | _ -> (-1, -1)

(* the value that `alloc_stack $T // name` produced — a variable's address *)
let slot_named (f : Sil.func) name =
  List.concat_map (fun (b : Sil.block) -> b.Sil.instrs) f.Sil.blocks
  |> List.find_map (function v, Sil.Alloc_stack n when n = name -> Some v | _ -> None)
  |> Option.get

(* the FIRST block (in creation order) that ends in a cond_br — f.blocks is reverse order *)
let the_cond_br (f : Sil.func) =
  let ordered = List.sort (fun (a : Sil.block) (b : Sil.block) -> compare a.Sil.bid b.Sil.bid) f.Sil.blocks in
  List.find (fun (b : Sil.block) -> match b.Sil.term with Sil.Cond_br _ -> true | _ -> false) ordered

let verifies src = Alcotest.(check (list string)) "verifier is silent" [] (Sil.verify (lower src))

(* ---- given: the memory model and the module skeleton (green before you start) ---- *)

let test_main () =
  let m = lower "print(1)" in
  Alcotest.(check bool) "top-level statements form @main" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "main") m.Sil.funcs)

let test_func () =
  let m = lower "func add(_ a: Int, _ b: Int) -> Int { return a + b }\nprint(add(1, 2))" in
  let f = func_named m "add" in
  Alcotest.(check int) "add has 2 params" 2 (List.length f.Sil.params);
  Alcotest.(check bool) "add returns Int" true (f.Sil.ret = Types.TInt)

let test_memory_model () =
  let main = main_of "let x = 1\nprint(x)" in
  Alcotest.(check bool) "alloc_stack for the binding" true (has_instr main is_alloc);
  Alcotest.(check bool) "store the initializer" true (has_instr main is_store);
  Alcotest.(check bool) "load on use" true (has_instr main is_load)

(* ---- TODO(08) if ---- *)

let test_if_diamond () =
  let main = main_of "let x = 1\nif x < 0 { print(x) } else { print(0) }\nprint(9)" in
  Alcotest.(check bool) "entry/then/else/merge" true (nblocks main >= 4);
  let t, e = cond_br_of (the_cond_br main) in
  Alcotest.(check bool) "cond_br has two targets" true (t >= 0 && e >= 0 && t <> e);
  (* both branches converge on one merge block, which is where the next statement went *)
  let merge = br_target (block main t) in
  Alcotest.(check int) "then and else both br to the merge" merge (br_target (block main e));
  Alcotest.(check bool) "the merge is a real block" true (merge >= 0)

let test_if_no_else () =
  let main = main_of "let x = 1\nif x > 0 { print(x) }\nprint(9)" in
  Alcotest.(check int) "entry/then/merge only" 3 (nblocks main);
  let t, e = cond_br_of (the_cond_br main) in
  Alcotest.(check int) "the false edge IS the merge" e (br_target (block main t))

let test_if_unreachable () =
  let f = func_named (lower "func pick(_ c: Bool) -> Int { if c { return 1 } else { return 2 } }\nprint(pick(true))") "pick" in
  Alcotest.(check bool) "the merge stays unreachable" true
    (List.exists (fun (b : Sil.block) -> b.Sil.term = Sil.Unreachable) f.Sil.blocks)

let test_if_verifies () = verifies "let n = 2\nif n == 1 { print(1) } else if n == 2 { print(2) } else { print(0) }"

(* ---- TODO(08) while ---- *)

let test_while_backedge () =
  let main = main_of "var n = 0\nwhile n < 3 { n = n + 1 }" in
  let backedge =
    List.exists (fun (b : Sil.block) -> match b.Sil.term with Sil.Br t -> t < b.Sil.bid | _ -> false) main.Sil.blocks
  in
  Alcotest.(check bool) "a block branches backwards" true backedge

let test_while_header () =
  let main = main_of "var n = 0\nwhile n < 3 { n = n + 1 }\nprint(n)" in
  let header = the_cond_br main in
  (* the condition is IN the header, so it is re-tested every trip *)
  Alcotest.(check bool) "the header re-loads n" true
    (List.exists (fun (_, i) -> is_load i) header.Sil.instrs);
  (* the entry falls in, the body branches back: two br's name the header *)
  Alcotest.(check int) "two blocks br to the header" 2 (List.length (preds_by_br main header.Sil.bid));
  Alcotest.(check bool) "entry is one of them" true (List.mem 0 (preds_by_br main header.Sil.bid))

let test_while_exit () =
  let main = main_of "var n = 0\nwhile n < 3 { n = n + 1 }\nprint(n)" in
  let _, e = cond_br_of (the_cond_br main) in
  Alcotest.(check bool) "the false edge leaves the loop" true
    (List.exists (fun (_, i) -> match i with Sil.Print _ -> true | _ -> false) (block main e).Sil.instrs)

let test_while_verifies () = verifies "var i = 0\nwhile i < 2 { var j = 0\n while j < 2 { j = j + 1 } \n i = i + 1 }"

(* ---- TODO(08) for ---- *)

let test_for_slot () =
  let main = main_of "for i in 0 ..< 3 { print(i) }" in
  Alcotest.(check bool) "a named slot for i" true
    (has_instr main (function Sil.Alloc_stack n -> n = "i" | _ -> false))

let test_for_hi_once () =
  (* `k + 1` is the bound: it must be computed in the entry block, not on every trip *)
  let main = main_of "var t = 0\nlet k = 2\nfor i in 0 ..< k + 1 { t = t + i }" in
  let entry = block main 0 in
  Alcotest.(check bool) "the bound is computed in bb0" true
    (List.exists (fun (_, i) -> match i with Sil.Binop (Ast.Add, _, _) -> true | _ -> false) entry.Sil.instrs)

let test_for_latch () =
  let main = main_of "for i in 0 ..< 3 { print(i) }" in
  let header = the_cond_br main in
  (* the increment lives in a block of its own, and that block carries the back-edge *)
  let latch =
    List.find
      (fun (b : Sil.block) ->
        b.Sil.bid <> 0 && br_target b = header.Sil.bid
        && List.exists (fun (_, i) -> match i with Sil.Binop (Ast.Add, _, _) -> true | _ -> false) b.Sil.instrs)
      main.Sil.blocks
  in
  Alcotest.(check bool) "the latch stores i back" true (List.exists (fun (_, i) -> is_store i) latch.Sil.instrs);
  Alcotest.(check bool) "the body is not the latch" true (latch.Sil.bid <> fst (cond_br_of header))

let test_for_verifies () = verifies "var s = 0\nfor i in 0 ..< 3 { for j in 0 ..< 3 { s = s + 1 } }"

(* ---- TODO(08) break ---- *)

let test_break_exit () =
  let main = main_of "var n = 0\nwhile n < 10 { n = n + 1\n if n > 3 { break } }\nprint(n)" in
  let _, exit_b = cond_br_of (the_cond_br main) in
  (* some block reaches the exit by a plain br: that is the `break` *)
  Alcotest.(check bool) "break branches to the loop exit" true (List.length (preds_by_br main exit_b) >= 1)

let test_break_inner_only () =
  let main = main_of "var s = 0\nfor i in 0 ..< 3 { for j in 0 ..< 3 { if j == 1 { break }\n s = s + 1 } }" in
  (* the break's block is empty and branches to the INNER loop's exit, never to the outer's *)
  let empties = List.filter (fun (b : Sil.block) -> b.Sil.instrs = [] && br_target b >= 0) main.Sil.blocks in
  Alcotest.(check bool) "an empty block just branches away" true (empties <> []);
  Alcotest.(check bool) "and it does not leave the outer loop" true
    (List.for_all (fun (b : Sil.block) -> br_target b <> 0) empties)

let test_break_verifies () = verifies "while true { if true { break } }\nprint(0)"

(* ---- TODO(08) continue ---- *)

let test_continue_header () =
  let main = main_of "var n = 0\nwhile n < 5 { n = n + 1\n if n == 2 { continue }\n print(n) }" in
  let header = the_cond_br main in
  (* the continue adds a third edge into the header: entry, fall-through, continue *)
  Alcotest.(check int) "three blocks br to the header" 3 (List.length (preds_by_br main header.Sil.bid))

let test_continue_latch () =
  let main = main_of "for i in 0 ..< 5 { if i == 2 { continue }\n print(i) }" in
  let header = the_cond_br main in
  let latch =
    List.find
      (fun (b : Sil.block) ->
        b.Sil.bid <> 0 && br_target b = header.Sil.bid && List.exists (fun (_, i) -> is_store i) b.Sil.instrs)
      main.Sil.blocks
  in
  (* THE bug this pins: continue must reach the latch, or the increment never runs *)
  Alcotest.(check int) "continue and fall-through hit the latch" 2 (List.length (preds_by_br main latch.Sil.bid));
  Alcotest.(check bool) "so it is not the header" true (latch.Sil.bid <> header.Sil.bid)

let test_continue_inner_only () =
  let main = main_of "var s = 0\nfor i in 0 ..< 3 { for j in 0 ..< 3 { if j == 1 { continue }\n s = s + 1 } }" in
  (* the latch of each loop is the block that stores back into that loop's counter *)
  let latch_of name =
    let slot = slot_named main name in
    List.find
      (fun (b : Sil.block) ->
        br_target b >= 0 && List.exists (fun (_, i) -> match i with Sil.Store (_, a) -> a = slot | _ -> false) b.Sil.instrs)
      main.Sil.blocks
  in
  (* the inner latch gains the continue's edge; the outer one is reached only by the inner exit *)
  Alcotest.(check int) "inner latch: fall-through + continue" 2 (List.length (preds_by_br main (latch_of "j").Sil.bid));
  Alcotest.(check int) "outer latch: untouched, one edge" 1 (List.length (preds_by_br main (latch_of "i").Sil.bid))

let test_continue_verifies () = verifies "var s = 0\nfor i in 0 ..< 3 { for j in 0 ..< 3 { if j == 1 { continue }\n s = s + 1 } }"

let () =
  Alcotest.run "silgen"
    [
      ( "given: memory model + module",
        [
          Alcotest.test_case "top-level becomes @main" `Quick test_main;
          Alcotest.test_case "a func lowers to a SIL func" `Quick test_func;
          Alcotest.test_case "alloc_stack/load/store" `Quick test_memory_model;
        ] );
      ( "hole: if",
        [
          Alcotest.test_case "diamond, both arms to merge" `Quick test_if_diamond;
          Alcotest.test_case "no else: false edge is merge" `Quick test_if_no_else;
          Alcotest.test_case "both return: merge unreachable" `Quick test_if_unreachable;
          Alcotest.test_case "an else-if chain verifies" `Quick test_if_verifies;
        ] );
      ( "hole: while",
        [
          Alcotest.test_case "the back-edge exists" `Quick test_while_backedge;
          Alcotest.test_case "condition lives in the header" `Quick test_while_header;
          Alcotest.test_case "the false edge is the exit" `Quick test_while_exit;
          Alcotest.test_case "nested loops verify" `Quick test_while_verifies;
        ] );
      ( "hole: for",
        [
          Alcotest.test_case "a named slot for the counter" `Quick test_for_slot;
          Alcotest.test_case "the bound is evaluated once" `Quick test_for_hi_once;
          Alcotest.test_case "the increment is its own block" `Quick test_for_latch;
          Alcotest.test_case "nested for loops verify" `Quick test_for_verifies;
        ] );
      ( "hole: break",
        [
          Alcotest.test_case "branches to the loop exit" `Quick test_break_exit;
          Alcotest.test_case "leaves only the inner loop" `Quick test_break_inner_only;
          Alcotest.test_case "while true + break verifies" `Quick test_break_verifies;
        ] );
      ( "hole: continue",
        [
          Alcotest.test_case "in a while: back to the header" `Quick test_continue_header;
          Alcotest.test_case "in a for: to the latch" `Quick test_continue_latch;
          Alcotest.test_case "targets the inner loop" `Quick test_continue_inner_only;
          Alcotest.test_case "continue in a nest verifies" `Quick test_continue_verifies;
        ] );
    ]
