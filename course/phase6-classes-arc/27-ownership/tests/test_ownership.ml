(* Alcotest unit tests for concept-27: the ownership verifier — fed both GOOD generated SIL
   and HAND-BUILT bad SIL (source code can't express the violations; the IR can). *)

let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
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

let test_good_code_verifies () =
  let m = lower "class T { var id: Int\n  init(_ i: Int) { id = i } }\nfunc f() {\n  let a = T(1)\n  let c = a\n  print(c.id)\n}\nf()" in
  Alcotest.(check (list string)) "generated SIL is ownership-clean" [] (Sil.verify_ownership m)

let test_leak () =
  (* an owned alloc_ref never consumed *)
  let m = mk_func [ (0, Sil.Alloc_ref "T") ] (Sil.Return None) in
  Alcotest.(check bool) "leak reported" true
    (List.exists (fun e -> e = "@t: owned value %0 is leaked (never consumed)") (Sil.verify_ownership m))

let test_double_destroy () =
  let m = mk_func [ (0, Sil.Alloc_ref "T"); (1, Sil.Destroy_value 0); (2, Sil.Destroy_value 0) ] (Sil.Return None) in
  Alcotest.(check bool) "double consume reported" true
    (List.exists (fun e -> e = "@t: owned value %0 consumed 2 times") (Sil.verify_ownership m))

let test_destroy_guaranteed () =
  (* destroying a guaranteed parameter = corrupting the caller's count *)
  let m = mk_func ~params:[ (0, Types.TClass "T") ] [ (1, Sil.Destroy_value 0) ] (Sil.Return None) in
  Alcotest.(check bool) "consumed borrow reported" true
    (List.exists (fun e -> e = "@t: guaranteed value %0 consumed without a copy_value") (Sil.verify_ownership m))

let test_use_after_consume () =
  let m =
    mk_func
      [ (0, Sil.Alloc_ref "T"); (1, Sil.Destroy_value 0); (2, Sil.Ref_element_addr (0, 0)) ]
      (Sil.Return None)
  in
  Alcotest.(check bool) "use-after-consume reported" true
    (List.exists (fun e -> e = "@t bb0: owned value %0 used after being consumed") (Sil.verify_ownership m))

let test_copy_fixes_borrow () =
  (* the legal version: copy the borrow, destroy the copy *)
  let m = mk_func ~params:[ (0, Types.TClass "T") ] [ (1, Sil.Copy_value 0); (2, Sil.Destroy_value 1) ] (Sil.Return None) in
  Alcotest.(check (list string)) "copy_value + destroy verifies" [] (Sil.verify_ownership m)

let () =
  Alcotest.run "ownership"
    [
      ("good", [ Alcotest.test_case "generated SIL clean" `Quick test_good_code_verifies;
                 Alcotest.test_case "copy of a borrow is legal" `Quick test_copy_fixes_borrow ]);
      ("bad", [ Alcotest.test_case "leak" `Quick test_leak;
                Alcotest.test_case "double destroy" `Quick test_double_destroy;
                Alcotest.test_case "destroy of a borrow" `Quick test_destroy_guaranteed;
                Alcotest.test_case "use after consume" `Quick test_use_after_consume ]);
    ]
