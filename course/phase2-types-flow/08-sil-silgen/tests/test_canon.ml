(* Tests for the NORMALISER the control-flow goldens compare against (`--emit-sil-canon`).

   It exists so those goldens test the graph you built rather than the order you built it in, and
   that only works if it is honest in both directions: two spellings of the same graph must come
   out identical, and two different graphs must stay different. Both halves are here, on CFGs
   built by hand — source cannot express "the same loop, but with the setup in its own block". *)

let ity = Types.TInt

(* a function from (bid, instrs in program order, terminator) triples; `instrs` are stored
   newest-first, the way the builder leaves them *)
let func (blocks : (int * (Sil.value * Sil.instr) list * Sil.term) list) :
    Sil.func =
  let val_ty = Hashtbl.create 16 in
  List.iter
    (fun (_, instrs, _) ->
      List.iter (fun (v, _) -> Hashtbl.replace val_ty v ity) instrs)
    blocks;
  {
    Sil.fname = "main";
    params = [];
    ret = Types.TVoid;
    val_ty;
    blocks =
      List.rev_map
        (fun (bid, instrs, term) -> { Sil.bid; instrs = List.rev instrs; term })
        blocks;
  }

let canon_text (f : Sil.func) : string =
  Sil.string_of_module (Canon.canon { Sil.funcs = [ f ] })

let same what a b = Alcotest.(check string) what (canon_text a) (canon_text b)

let differ what a b =
  Alcotest.(check bool)
    what true
    (String.compare (canon_text a) (canon_text b) <> 0)

(* ---- the same graph, spelled differently -------------------------------------------------- *)

(* A loop: entry seeds a slot, header tests, body, latch increments, exit returns. *)
let loop_inline =
  func
    [
      ( 0,
        [ (0, Sil.Alloc_stack "i"); (1, Sil.Int_lit 0); (2, Sil.Store (1, 0)) ],
        Sil.Br 1 );
      ( 1,
        [ (3, Sil.Load 0); (4, Sil.Int_lit 3); (5, Sil.Binop (Ast.Lt, 3, 4)) ],
        Sil.Cond_br (5, 2, 4) );
      (2, [ (6, Sil.Print 3) ], Sil.Br 3);
      ( 3,
        [
          (7, Sil.Load 0);
          (8, Sil.Int_lit 1);
          (9, Sil.Binop (Ast.Add, 7, 8));
          (10, Sil.Store (9, 0));
        ],
        Sil.Br 1 );
      (4, [], Sil.Return None);
    ]

(* the same loop, but the setup went into a block of its own — the choice that started all this *)
let loop_setup_block =
  func
    [
      (0, [], Sil.Br 5);
      ( 5,
        [ (0, Sil.Alloc_stack "i"); (1, Sil.Int_lit 0); (2, Sil.Store (1, 0)) ],
        Sil.Br 1 );
      ( 1,
        [ (3, Sil.Load 0); (4, Sil.Int_lit 3); (5, Sil.Binop (Ast.Lt, 3, 4)) ],
        Sil.Cond_br (5, 2, 4) );
      (2, [ (6, Sil.Print 3) ], Sil.Br 3);
      ( 3,
        [
          (7, Sil.Load 0);
          (8, Sil.Int_lit 1);
          (9, Sil.Binop (Ast.Add, 7, 8));
          (10, Sil.Store (9, 0));
        ],
        Sil.Br 1 );
      (4, [], Sil.Return None);
    ]

(* the same loop again, with the blocks created in a different order (so, different ids) *)
let loop_renumbered =
  func
    [
      ( 0,
        [ (0, Sil.Alloc_stack "i"); (1, Sil.Int_lit 0); (2, Sil.Store (1, 0)) ],
        Sil.Br 9 );
      ( 9,
        [ (3, Sil.Load 0); (4, Sil.Int_lit 3); (5, Sil.Binop (Ast.Lt, 3, 4)) ],
        Sil.Cond_br (5, 7, 8) );
      (7, [ (6, Sil.Print 3) ], Sil.Br 6);
      ( 6,
        [
          (7, Sil.Load 0);
          (8, Sil.Int_lit 1);
          (9, Sil.Binop (Ast.Add, 7, 8));
          (10, Sil.Store (9, 0));
        ],
        Sil.Br 9 );
      (8, [], Sil.Return None);
    ]

(* and again, with the loop bound emitted in the entry instead of the header, and the values
   numbered from a different starting point *)
let loop_other_values =
  func
    [
      ( 0,
        [
          (40, Sil.Alloc_stack "i");
          (41, Sil.Int_lit 0);
          (42, Sil.Store (41, 40));
        ],
        Sil.Br 1 );
      ( 1,
        [
          (43, Sil.Load 40);
          (44, Sil.Int_lit 3);
          (45, Sil.Binop (Ast.Lt, 43, 44));
        ],
        Sil.Cond_br (45, 2, 4) );
      (2, [ (46, Sil.Print 43) ], Sil.Br 3);
      ( 3,
        [
          (47, Sil.Load 40);
          (48, Sil.Int_lit 1);
          (49, Sil.Binop (Ast.Add, 47, 48));
          (50, Sil.Store (49, 40));
        ],
        Sil.Br 1 );
      (4, [], Sil.Return None);
    ]

let test_setup_block () =
  same "a setup block folds into its only predecessor" loop_inline
    loop_setup_block

let test_block_ids () =
  same "block ids follow the graph, not creation order" loop_inline
    loop_renumbered

let test_value_ids () =
  same "values are renumbered from their definitions" loop_inline
    loop_other_values

let test_chain () =
  (* three empty blocks in a row still lead to the same place *)
  let chained =
    func
      [
        (0, [], Sil.Br 5);
        (5, [], Sil.Br 6);
        ( 6,
          [
            (0, Sil.Alloc_stack "i"); (1, Sil.Int_lit 0); (2, Sil.Store (1, 0));
          ],
          Sil.Br 1 );
        ( 1,
          [ (3, Sil.Load 0); (4, Sil.Int_lit 3); (5, Sil.Binop (Ast.Lt, 3, 4)) ],
          Sil.Cond_br (5, 2, 4) );
        (2, [ (6, Sil.Print 3) ], Sil.Br 3);
        ( 3,
          [
            (7, Sil.Load 0);
            (8, Sil.Int_lit 1);
            (9, Sil.Binop (Ast.Add, 7, 8));
            (10, Sil.Store (9, 0));
          ],
          Sil.Br 1 );
        (4, [], Sil.Return None);
      ]
  in
  same "a chain of forwarding blocks folds too" loop_inline chained

let test_literal_placement () =
  (* the bound emitted before the load rather than after it: a literal has no operands and no
     effects, so where it sits is not a difference the goldens should see *)
  let late =
    func
      [
        ( 0,
          [
            (0, Sil.Alloc_stack "i"); (1, Sil.Int_lit 0); (2, Sil.Store (1, 0));
          ],
          Sil.Br 1 );
        ( 1,
          [ (4, Sil.Int_lit 3); (3, Sil.Load 0); (5, Sil.Binop (Ast.Lt, 3, 4)) ],
          Sil.Cond_br (5, 2, 4) );
        (2, [ (6, Sil.Print 3) ], Sil.Br 3);
        ( 3,
          [
            (7, Sil.Load 0);
            (8, Sil.Int_lit 1);
            (9, Sil.Binop (Ast.Add, 7, 8));
            (10, Sil.Store (9, 0));
          ],
          Sil.Br 1 );
        (4, [], Sil.Return None);
      ]
  in
  same "a literal's position in its block does not count" loop_inline late

(* ---- graphs that are genuinely different must stay different ------------------------------ *)

let test_continue_to_header () =
  (* THE bug the concept warns about: the back edge skips the latch, so `i` never advances *)
  let skips_latch =
    func
      [
        ( 0,
          [
            (0, Sil.Alloc_stack "i"); (1, Sil.Int_lit 0); (2, Sil.Store (1, 0));
          ],
          Sil.Br 1 );
        ( 1,
          [ (3, Sil.Load 0); (4, Sil.Int_lit 3); (5, Sil.Binop (Ast.Lt, 3, 4)) ],
          Sil.Cond_br (5, 2, 4) );
        (2, [ (6, Sil.Print 3) ], Sil.Br 1);
        ( 3,
          [
            (7, Sil.Load 0);
            (8, Sil.Int_lit 1);
            (9, Sil.Binop (Ast.Add, 7, 8));
            (10, Sil.Store (9, 0));
          ],
          Sil.Br 1 );
        (4, [], Sil.Return None);
      ]
  in
  differ "a body that branches past the latch is a different graph" loop_inline
    skips_latch

let test_swapped_arms () =
  let swapped =
    func
      [
        ( 0,
          [
            (0, Sil.Alloc_stack "i"); (1, Sil.Int_lit 0); (2, Sil.Store (1, 0));
          ],
          Sil.Br 1 );
        ( 1,
          [ (3, Sil.Load 0); (4, Sil.Int_lit 3); (5, Sil.Binop (Ast.Lt, 3, 4)) ],
          Sil.Cond_br (5, 4, 2) );
        (2, [ (6, Sil.Print 3) ], Sil.Br 3);
        ( 3,
          [
            (7, Sil.Load 0);
            (8, Sil.Int_lit 1);
            (9, Sil.Binop (Ast.Add, 7, 8));
            (10, Sil.Store (9, 0));
          ],
          Sil.Br 1 );
        (4, [], Sil.Return None);
      ]
  in
  differ "swapping the true and false edges is a different graph" loop_inline
    swapped

let test_missing_store () =
  let no_store =
    func
      [
        ( 0,
          [
            (0, Sil.Alloc_stack "i"); (1, Sil.Int_lit 0); (2, Sil.Store (1, 0));
          ],
          Sil.Br 1 );
        ( 1,
          [ (3, Sil.Load 0); (4, Sil.Int_lit 3); (5, Sil.Binop (Ast.Lt, 3, 4)) ],
          Sil.Cond_br (5, 2, 4) );
        (2, [ (6, Sil.Print 3) ], Sil.Br 3);
        ( 3,
          [
            (7, Sil.Load 0); (8, Sil.Int_lit 1); (9, Sil.Binop (Ast.Add, 7, 8));
          ],
          Sil.Br 1 );
        (4, [], Sil.Return None);
      ]
  in
  differ "an increment that never stores is a different graph" loop_inline
    no_store

let test_load_across_store () =
  (* a load moved past a store is NOT normalised away: reordering memory operations is exactly
     what a compiler may not do on its own, so the goldens still see it *)
  let moved =
    func
      [
        ( 0,
          [
            (1, Sil.Int_lit 0);
            (0, Sil.Alloc_stack "i");
            (2, Sil.Store (1, 0));
            (11, Sil.Load 0);
          ],
          Sil.Br 1 );
        ( 1,
          [ (3, Sil.Load 0); (4, Sil.Int_lit 3); (5, Sil.Binop (Ast.Lt, 3, 4)) ],
          Sil.Cond_br (5, 2, 4) );
        (2, [ (6, Sil.Print 3) ], Sil.Br 3);
        ( 3,
          [
            (7, Sil.Load 0);
            (8, Sil.Int_lit 1);
            (9, Sil.Binop (Ast.Add, 7, 8));
            (10, Sil.Store (9, 0));
          ],
          Sil.Br 1 );
        (4, [], Sil.Return None);
      ]
  in
  differ "an extra load is still visible" loop_inline moved

let () =
  Alcotest.run "canon"
    [
      ( "the same graph, spelled differently",
        [
          Alcotest.test_case "a setup block folds away" `Quick test_setup_block;
          Alcotest.test_case "block ids follow the graph" `Quick test_block_ids;
          Alcotest.test_case "value ids are renumbered" `Quick test_value_ids;
          Alcotest.test_case "a chain of forwarders folds" `Quick test_chain;
          Alcotest.test_case "a literal's position" `Quick
            test_literal_placement;
        ] );
      ( "different graphs stay different",
        [
          Alcotest.test_case "back edge skipping the latch" `Quick
            test_continue_to_header;
          Alcotest.test_case "swapped true/false edges" `Quick test_swapped_arms;
          Alcotest.test_case "an increment that never stores" `Quick
            test_missing_store;
          Alcotest.test_case "memory operations are not moved" `Quick
            test_load_across_store;
        ] );
    ]
