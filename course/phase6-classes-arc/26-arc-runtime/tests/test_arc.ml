(* Alcotest unit tests for concept-26: ARC insertion shapes + the runtime contract. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  Silgen.lower p

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let in_func (m : Sil.modul) (name : string) (pred : Sil.instr -> bool) : int =
  match List.find_opt (fun (f : Sil.func) -> f.Sil.fname = name) m.Sil.funcs with
  | Some f -> List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) 0 f.Sil.blocks
  | None -> -1

let tracer = "class T { var id: Int\n  init(_ i: Int) { id = i }\n  deinit { print(id) } }\n"
let is_retain = function Sil.Retain _ -> true | _ -> false
let is_release = function Sil.Release _ -> true | _ -> false

let test_borrow_retains () =
  (* `let c = a` borrows a slot's value: a retain must balance c's scope-end release *)
  let m = lower (tracer ^ "func f() {\n  let a = T(1)\n  let c = a\n  print(c.id)\n}\nf()") in
  Alcotest.(check int) "one retain in f (the borrow)" 1 (in_func m "f" is_retain);
  Alcotest.(check int) "two releases in f (both locals)" 2 (in_func m "f" is_release)

let test_fresh_consumed () =
  (* `let a = T(1)` consumes the fresh +1 — no retain at all *)
  let m = lower (tracer ^ "func f() {\n  let a = T(1)\n  print(a.id)\n}\nf()") in
  Alcotest.(check int) "no retain for a consumed fresh value" 0 (in_func m "f" is_retain);
  Alcotest.(check int) "one release (scope end)" 1 (in_func m "f" is_release)

let test_destructor_synthesized () =
  let m = lower (tracer ^ "print(1)") in
  Alcotest.(check bool) "T.deinit exists" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "T.deinit") m.Sil.funcs)

let test_destructor_chains () =
  (* the TWO chains: B.deinit (bodies) chains to A.deinit; B.destroy releases B's own class
     field and chains to A.destroy FIRST (base fields die before derived's) *)
  let m = lower ("class L { var id: Int\n  init(_ i: Int) { id = i } }\nclass A { var x: Int\n  init(_ v: Int) { x = v } }\nclass B: A { var l: L\n  init(_ v: Int, _ l0: L) { l = l0\n    super.init(v) } }\nprint(1)") in
  let refs_in fname target =
    match List.find_opt (fun (f : Sil.func) -> f.Sil.fname = fname) m.Sil.funcs with
    | Some f ->
        List.exists
          (fun (b : Sil.block) ->
            List.exists (fun (_, i) -> match i with Sil.Func_ref n -> n = target | _ -> false) b.Sil.instrs)
          f.Sil.blocks
    | None -> false
  in
  Alcotest.(check int) "B.destroy releases B's field" 1 (in_func m "B.destroy" is_release);
  Alcotest.(check int) "B.deinit releases nothing (bodies only)" 0 (in_func m "B.deinit" is_release);
  Alcotest.(check bool) "B.deinit chains to A.deinit" true (refs_in "B.deinit" "A.deinit");
  Alcotest.(check bool) "B.destroy chains to A.destroy" true (refs_in "B.destroy" "A.destroy")

let test_optimizer_preserves () =
  let m = Opt.optimize (lower (tracer ^ "func f() {\n  let a = T(1)\n  let c = a\n  print(c.id)\n}\nf()")) in
  Alcotest.(check bool) "retains survive -O" true (count_instr is_retain m >= 1);
  Alcotest.(check bool) "releases survive -O" true (count_instr is_release m >= 2);
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let () =
  Alcotest.run "arc"
    [
      ("ownership", [ Alcotest.test_case "borrow retains" `Quick test_borrow_retains;
                      Alcotest.test_case "fresh consumed" `Quick test_fresh_consumed ]);
      ("destructors", [ Alcotest.test_case "synthesized" `Quick test_destructor_synthesized;
                        Alcotest.test_case "the two chains" `Quick test_destructor_chains ]);
      ("optimizer", [ Alcotest.test_case "-O keeps ARC ops" `Quick test_optimizer_preserves ]);
    ]
