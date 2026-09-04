(* Alcotest for concept 27: the ownership verifier, fed both GOOD generated SIL and HAND-BUILT
   bad SIL. This is the one place the three rules separate — source code cannot express a
   violation, because SILGen is the only thing that writes this IR. The IR can. *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  Silgen.lower p

(* a tiny hand-built function: %0 is a class param (guaranteed); body per test *)
let mk_func ?(params = []) (instrs : (Sil.value * Sil.instr) list) (term : Sil.term) : Sil.modul =
  let val_ty = Hashtbl.create 8 in
  List.iter (fun (v, t) -> Hashtbl.replace val_ty v t) params;
  (* give every result a class type so the verifier classifies it *)
  List.iter (fun (v, _) -> if not (Hashtbl.mem val_ty v) then Hashtbl.replace val_ty v (Types.TClass "T")) instrs;
  let blk = { Sil.bid = 0; args = []; instrs = List.rev instrs; term } in
  let f = { Sil.fname = "t"; params = List.map (fun (v, t) -> (v, t)) params; ret = Types.TVoid;
            generic = false; blocks = [ blk ]; val_ty } in
  { Sil.funcs = [ f ]; structs = []; enums = []; protos = []; classes = []; wtables = [] }

let tracer = "class T { var id: Int\n  init(_ i: Int) { id = i }\n  deinit { print(id) } }\n"

let clean (label : string) (src : string) : unit =
  Alcotest.(check (list string)) label [] (Sil.verify_ownership (lower src))

(* ---- the verifier accepts everything SILGen really generates ---- *)

let test_straight_line () =
  clean "borrow, copy, call"
    (tracer ^ "func use(_ t: T) -> Int { return t.id }\n\
               func f() {\n  let a = T(1)\n  let c = a\n  print(use(c))\n}\nf()")

let test_control_flow () =
  clean "early return, break, continue"
    (tracer
   ^ "func early(_ n: Int) -> Int { let a = T(n)\n  if a.id > 2 { return a.id }\n  return 0 }\n\
      func loops() {\n  var i = 0\n  while i < 4 {\n    let t = T(i)\n    i = i + 1\n\
     \    if t.id == 1 { continue }\n    if t.id == 2 { break }\n    print(t.id)\n  }\n}\n\
      print(early(5))\nloops()")

let test_fields_and_self () =
  clean "fields, self, destructors"
    ("class L { var id: Int\n  init(_ i: Int) { id = i }\n  deinit { print(id) } }\n\
      class Box { var l: L\n  var n: Int\n  init(_ x: L) { self.l = x\n    self.n = 0 }\n\
     \  func put(_ x: L) { self.l = x }\n  deinit { print(0) } }\n\
      func f() { let b = Box(L(1))\n  b.put(L(2))\n  print(b.n) }\nf()")

let test_inheritance () =
  clean "override, super.init, dispatch"
    ("class A { var x: Int\n  init(_ v: Int) { x = v }\n  func f() -> Int { return 1 }\n\
     \  func g() -> Int { return f() + 100 }\n  deinit { print(x) } }\n\
      class B: A { var y: Int\n  init(_ v: Int, _ w: Int) { y = w\n    super.init(v) }\n\
     \  override func f() -> Int { return y }\n  deinit { print(y) } }\n\
      func run() { let b: A = B(1, 2)\n  print(b.g()) }\nrun()")

let test_copy_fixes_borrow () =
  (* the legal shape a borrow needs before it can be consumed *)
  let m = mk_func ~params:[ (0, Types.TClass "T") ] [ (1, Sil.Copy_value 0); (2, Sil.Destroy_value 1) ] (Sil.Return None) in
  Alcotest.(check (list string)) "copy_value + destroy verifies" [] (Sil.verify_ownership m)

(* ---- R1: an owned value is consumed exactly once ---- *)

let test_leak () =
  let m = mk_func [ (0, Sil.Alloc_ref "T") ] (Sil.Return None) in
  Alcotest.(check bool) "leak reported" true
    (List.exists (fun e -> e = "@t: owned value %0 is leaked (never consumed)") (Sil.verify_ownership m))

let test_double_destroy () =
  let m = mk_func [ (0, Sil.Alloc_ref "T"); (1, Sil.Destroy_value 0); (2, Sil.Destroy_value 0) ] (Sil.Return None) in
  Alcotest.(check bool) "double consume reported" true
    (List.exists (fun e -> e = "@t: owned value %0 consumed 2 times") (Sil.verify_ownership m))

let test_store_consumes () =
  (* a store is a consume too, so alloc_ref + store + destroy is TWO consumes, not one *)
  let m =
    mk_func
      [ (0, Sil.Alloc_ref "T"); (1, Sil.Alloc_stack "s"); (2, Sil.Store (0, 1)); (3, Sil.Destroy_value 0) ]
      (Sil.Return None)
  in
  Alcotest.(check bool) "a store counts as a consume" true
    (List.exists (fun e -> e = "@t: owned value %0 consumed 2 times") (Sil.verify_ownership m))

(* ---- R2: a guaranteed value is never consumed ---- *)

let test_destroy_guaranteed () =
  (* destroying a guaranteed parameter = corrupting the caller's count *)
  let m = mk_func ~params:[ (0, Types.TClass "T") ] [ (1, Sil.Destroy_value 0) ] (Sil.Return None) in
  Alcotest.(check bool) "consumed borrow reported" true
    (List.exists (fun e -> e = "@t: guaranteed value %0 consumed without a copy_value") (Sil.verify_ownership m))

let test_store_of_a_borrow () =
  (* the exact bug the verifier found in its own SILGen: spilling a class param to a slot
     STORES a borrow, and a store consumes *)
  let m =
    mk_func ~params:[ (0, Types.TClass "T") ]
      [ (1, Sil.Alloc_stack "self"); (2, Sil.Store (0, 1)) ]
      (Sil.Return None)
  in
  Alcotest.(check bool) "spilling a param is R2" true
    (List.exists (fun e -> e = "@t: guaranteed value %0 consumed without a copy_value") (Sil.verify_ownership m))

(* ---- R3: nothing is used after its consume ---- *)

let test_use_after_consume () =
  let m =
    mk_func
      [ (0, Sil.Alloc_ref "T"); (1, Sil.Destroy_value 0); (2, Sil.Ref_element_addr (0, 0)) ]
      (Sil.Return None)
  in
  Alcotest.(check bool) "use-after-consume reported" true
    (List.exists (fun e -> e = "@t bb0: owned value %0 used after being consumed" ) (Sil.verify_ownership m))

let test_use_before_is_fine () =
  (* the same instructions in the legal order say nothing at all *)
  let m =
    mk_func
      [ (0, Sil.Alloc_ref "T"); (1, Sil.Ref_element_addr (0, 0)); (2, Sil.Destroy_value 0) ]
      (Sil.Return None)
  in
  Alcotest.(check (list string)) "use then consume verifies" [] (Sil.verify_ownership m)

(* ---- the structured operations the verifier is checking ---- *)

let count (m : Sil.modul) (pred : Sil.instr -> bool) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let test_structured_ops () =
  let m = lower (tracer ^ "func f() {\n  let a = T(1)\n  let c = a\n  print(c.id)\n}\nf()") in
  Alcotest.(check int) "one copy_value (the borrow)" 1 (count m (function Sil.Copy_value _ -> true | _ -> false));
  Alcotest.(check int) "two load [take] (both slots)" 2 (count m (function Sil.Load_take _ -> true | _ -> false));
  Alcotest.(check int) "two destroy_value" 2 (count m (function Sil.Destroy_value _ -> true | _ -> false));
  (* and every consume is of a value that OWNS: each destroy_value takes a `load [take]`
     result, never a plain borrow. Concept 26's Retain/Release no longer exist as instructions
     at all — the recast replaced them rather than sitting beside them. *)
  let takes = Hashtbl.create 4 in
  List.iter
    (fun (f : Sil.func) ->
      List.iter
        (fun (b : Sil.block) ->
          List.iter (fun (v, i) -> match i with Sil.Load_take _ -> Hashtbl.replace takes v () | _ -> ()) b.Sil.instrs)
        f.Sil.blocks)
    m.Sil.funcs;
  let destroys_of_takes =
    count m (function Sil.Destroy_value v -> Hashtbl.mem takes v | _ -> false)
  in
  Alcotest.(check int) "every destroy consumes a take" 2 destroys_of_takes

let test_params_are_not_spilled () =
  (* the design the verifier forced: a class param has no slot and no entry store *)
  let m = lower (tracer ^ "func use(_ t: T) -> Int { return t.id }\nfunc f() { let a = T(1)\n  print(use(a)) }\nf()") in
  let use = List.find (fun (f : Sil.func) -> f.Sil.fname = "use") m.Sil.funcs in
  let body = List.concat_map (fun (b : Sil.block) -> List.map snd b.Sil.instrs) use.Sil.blocks in
  Alcotest.(check int) "no alloc_stack in the callee" 0
    (List.length (List.filter (function Sil.Alloc_stack _ -> true | _ -> false) body));
  Alcotest.(check int) "and no entry store" 0
    (List.length (List.filter (function Sil.Store _ -> true | _ -> false) body))

let () =
  Alcotest.run "ownership"
    [
      ( "generated SIL",
        [ Alcotest.test_case "straight line" `Quick test_straight_line;
          Alcotest.test_case "control flow" `Quick test_control_flow;
          Alcotest.test_case "fields and self" `Quick test_fields_and_self;
          Alcotest.test_case "inheritance" `Quick test_inheritance;
          Alcotest.test_case "a copied borrow is legal" `Quick test_copy_fixes_borrow ] );
      ( "R1 exactly once",
        [ Alcotest.test_case "leak" `Quick test_leak;
          Alcotest.test_case "double destroy" `Quick test_double_destroy;
          Alcotest.test_case "a store consumes too" `Quick test_store_consumes ] );
      ( "R2 never a borrow",
        [ Alcotest.test_case "destroy of a borrow" `Quick test_destroy_guaranteed;
          Alcotest.test_case "spilling a param" `Quick test_store_of_a_borrow ] );
      ( "R3 no use after",
        [ Alcotest.test_case "use after consume" `Quick test_use_after_consume;
          Alcotest.test_case "use before is fine" `Quick test_use_before_is_fine ] );
      ( "the ops it checks",
        [ Alcotest.test_case "copy / take / destroy" `Quick test_structured_ops;
          Alcotest.test_case "params stay in registers" `Quick test_params_are_not_spilled ] );
    ]
