(* ---------------------------------------------------------------------------------------- *)
(* CANONICAL SIL.                                                                            *)
(*                                                                                           *)
(* Two correct lowerings of the same program can differ in ways this concept never asks about: *)
(* which order the blocks were created in (block ids follow creation), and whether the setup   *)
(* of a loop got a block of its own (an extra block that only branches). Both change every id  *)
(* in the printed output without changing the graph. Comparing text after canonicalising means *)
(* the tests compare the CFG you built, not the order you happened to build it in.             *)
(*                                                                                             *)
(*   1. fold FORWARDING blocks — no instructions, terminator is a plain `br` — into their      *)
(*      target, so an extra block that only passes control through disappears;                 *)
(*   2. renumber blocks by a depth-first walk from the entry, so ids follow the shape;         *)
(*   3. renumber values by order of definition.                                                *)
(*                                                                                             *)
(* Nothing here is part of the lesson; it exists so the goldens can be about the lesson. *)

let canon_func (f : Sil.func) : Sil.func =
  (* a working copy: (bid, instrs in program order, terminator) *)
  let blocks =
    ref
      (List.map
         (fun (b : Sil.block) -> (b.Sil.bid, List.rev b.Sil.instrs, b.Sil.term))
         (List.rev f.Sil.blocks))
  in
  let term_of bid =
    let _, _, t = List.find (fun (i, _, _) -> i = bid) !blocks in
    t
  in
  let exists bid = List.exists (fun (i, _, _) -> i = bid) !blocks in
  let succs = function
    | Sil.Br t -> [ t ]
    | Sil.Cond_br (_, t, e) -> [ t; e ]
    | _ -> []
  in
  let preds bid =
    List.filter (fun (i, _, t) -> i <> bid && List.mem bid (succs t)) !blocks
    |> List.map (fun (i, _, _) -> i)
  in

  (* MERGE: a block reached only by a plain `br`, from one place, belongs to that place. This is
     what makes "did you open a block for the loop setup?" stop mattering — either way the
     instructions end up in the same block here. (Concept 17 does this for real, as an
     optimisation; here it only normalises what we compare.) *)
  let merged = ref true in
  while !merged do
    merged := false;
    match
      List.find_opt
        (fun (bid, _, t) ->
          match t with
          | Sil.Br tgt ->
              tgt <> bid && tgt <> 0 && exists tgt && preds tgt = [ bid ]
          | _ -> false)
        !blocks
    with
    | None -> ()
    | Some (bid, instrs, t) ->
        let tgt = match t with Sil.Br x -> x | _ -> assert false in
        let _, tgt_instrs, tgt_term =
          List.find (fun (i, _, _) -> i = tgt) !blocks
        in
        blocks :=
          List.filter_map
            (fun (i, ins, tm) ->
              if i = tgt then None
              else if i = bid then Some (bid, instrs @ tgt_instrs, tgt_term)
              else Some (i, ins, tm))
            !blocks;
        merged := true
  done;

  (* HOIST the slots. `alloc_stack` reserves space; where it sits among the instructions is not
     observable, and IRGen hoists every alloca to the entry block anyway (concept 09). Putting
     them all first, in their original relative order, means "did you allocate before or after
     evaluating the bound?" stops being a difference the goldens can see. *)
  let allocs, rest =
    List.fold_left
      (fun (a, r) (bid, instrs, term) ->
        let mine, others =
          List.partition
            (fun (_, i) ->
              match i with Sil.Alloc_stack _ -> true | _ -> false)
            instrs
        in
        (a @ mine, r @ [ (bid, others, term) ]))
      ([], []) !blocks
  in
  blocks :=
    List.map
      (fun (bid, instrs, term) ->
        if bid = 0 then (bid, allocs @ instrs, term) else (bid, instrs, term))
      rest;

  (* HOIST the constants too, to the top of the block that defines them. A literal has no
     operands and no effects, so emitting it early or late is not observable — but it moves
     every number after it. Same reason as the slots. *)
  let is_const = function
    | Sil.Int_lit _ | Sil.Float_lit _ | Sil.Bool_lit _ | Sil.String_lit _
    | Sil.Func_ref _ ->
        true
    | _ -> false
  in
  blocks :=
    List.map
      (fun (bid, instrs, term) ->
        let consts, others = List.partition (fun (_, i) -> is_const i) instrs in
        (bid, consts @ others, term))
      !blocks;

  (* RENUMBER: blocks depth-first from the entry, values in order of definition *)
  let order = ref [] and seen = Hashtbl.create 8 in
  let rec walk bid =
    if exists bid && not (Hashtbl.mem seen bid) then (
      Hashtbl.replace seen bid ();
      order := bid :: !order;
      List.iter walk (succs (term_of bid)))
  in
  walk 0;
  let order = List.rev !order in
  let bmap = Hashtbl.create 8 in
  List.iteri (fun i bid -> Hashtbl.replace bmap bid i) order;
  let bid_of b = try Hashtbl.find bmap b with Not_found -> b in

  let vmap = Hashtbl.create 16 in
  let next = ref 0 in
  let define v =
    if not (Hashtbl.mem vmap v) then (
      Hashtbl.replace vmap v !next;
      incr next)
  in
  List.iter (fun (v, _) -> define v) f.Sil.params;
  List.iter
    (fun bid ->
      let _, instrs, _ = List.find (fun (i, _, _) -> i = bid) !blocks in
      List.iter (fun (v, _) -> define v) instrs)
    order;
  let vv v = try Hashtbl.find vmap v with Not_found -> v in

  let re_instr : Sil.instr -> Sil.instr = function
    | Sil.Load a -> Sil.Load (vv a)
    | Sil.Store (v, a) -> Sil.Store (vv v, vv a)
    | Sil.Binop (op, l, r) -> Sil.Binop (op, vv l, vv r)
    | Sil.Unop (op, v) -> Sil.Unop (op, vv v)
    | Sil.Apply (fn, args) -> Sil.Apply (vv fn, List.map vv args)
    | Sil.Print v -> Sil.Print (vv v)
    | keep -> keep
  in
  let re_term : Sil.term -> Sil.term = function
    | Sil.Br t -> Sil.Br (bid_of t)
    | Sil.Cond_br (c, t, e) -> Sil.Cond_br (vv c, bid_of t, bid_of e)
    | Sil.Return (Some v) -> Sil.Return (Some (vv v))
    | keep -> keep
  in
  let val_ty = Hashtbl.create 16 in
  Hashtbl.iter (fun v t -> Hashtbl.replace val_ty (vv v) t) f.Sil.val_ty;
  {
    f with
    params = List.map (fun (v, t) -> (vv v, t)) f.Sil.params;
    val_ty;
    blocks =
      List.rev_map
        (fun bid ->
          let _, instrs, term = List.find (fun (i, _, _) -> i = bid) !blocks in
          {
            Sil.bid = bid_of bid;
            (* stored newest-first, as the printer expects *)
            instrs = List.rev_map (fun (v, i) -> (vv v, re_instr i)) instrs;
            term = re_term term;
          })
        order;
  }

let canon (m : Sil.modul) : Sil.modul =
  { Sil.funcs = List.map canon_func m.Sil.funcs }
