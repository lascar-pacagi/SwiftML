(* The SIL optimizer — concept 17 (skeleton). Builds on 15 (pass manager) + 16 (mem2reg). The new
   work generalizes constant folding (comparisons + bools) and adds CFG simplification (fold a branch
   on a constant, delete the dead block). You fill the TODO(17) holes: fold_binop + simplify_cfg.
   Reference: solution/opt.ml. *)

type pass = { name : string; run : Sil.func -> Sil.func }

(* ---- the operands an instruction reads / a terminator reads (used by analyses) ---- *)
let operands : Sil.instr -> Sil.value list = function
  | Sil.Int_lit _ | Sil.Float_lit _ | Sil.Bool_lit _ | Sil.String_lit _ | Sil.Func_ref _ | Sil.Alloc_stack _ -> []
  | Sil.Load a -> [ a ]
  | Sil.Store (x, a) -> [ x; a ]
  | Sil.Binop (_, a, b) -> [ a; b ]
  | Sil.Unop (_, a) -> [ a ]
  | Sil.Apply (g, args) -> g :: args
  | Sil.Print a -> [ a ]
  | Sil.Struct fs -> fs
  | Sil.Struct_extract (a, _) -> [ a ]
  | Sil.Struct_element_addr (a, _) -> [ a ]
  | Sil.Enum (_, payload) -> payload
  | Sil.Enum_tag a -> [ a ]
  | Sil.Enum_payload (a, _) -> [ a ]

let term_operands : Sil.term -> Sil.value list = function
  | Sil.Br (_, args) -> args
  | Sil.Cond_br (c, (_, ta), (_, ea)) -> (c :: ta) @ ea
  | Sil.Return (Some v) -> [ v ]
  | _ -> []

(* an instruction we must keep even if its result is unused (it does something observable) *)
let has_side_effect : Sil.instr -> bool = function
  | Sil.Store _ | Sil.Apply _ | Sil.Print _ -> true
  | _ -> false

(* ---- the pass manager: run the pipeline over each function ---- *)
let run_pipeline ?(log = false) (passes : pass list) (m : Sil.modul) : Sil.modul =
  let run_func (f : Sil.func) =
    List.fold_left
      (fun f p ->
        if log then Printf.eprintf "  sil-opt: [%-16s] @%s\n" p.name f.Sil.fname;
        p.run f)
      f passes
  in
  { m with Sil.funcs = List.map run_func m.Sil.funcs }

(* ---- pass: constant propagation + folding (concept 17 generalizes concept 15: now Int
   arithmetic, integer/bool comparisons, and &&/||). On SSA (after mem2reg) a `let` is already a
   value, so folding propagates through it. ---- *)
type cst = CInt of int | CBool of bool

let cst_to_instr = function CInt n -> Sil.Int_lit n | CBool b -> Sil.Bool_lit b

let fold_binop (op : Ast.binop) (a : cst) (b : cst) : cst option =
  (* TODO(17): evaluate a binary op on two known constants, returning the resulting constant.
       - two CInt x,y: Add/Sub/Mul -> CInt; Div/Mod -> CInt but RETURN None when y = 0 (so the
         runtime trap is preserved); the six comparisons Eq/Ne/Lt/Le/Gt/Ge -> CBool.
       - two CBool p,q: Eq/Ne -> CBool; And/Or -> CBool.
       - anything else -> None. *)
  ignore (op, a, b);
  None

let fold_unop (op : Ast.unop) (a : cst) : cst option =
  match (op, a) with Ast.Neg, CInt x -> Some (CInt (-x)) | _ -> None

let constant_fold (f : Sil.func) : Sil.func =
  let cst : (Sil.value, cst) Hashtbl.t = Hashtbl.create 64 in (* values known to be constants *)
  let get v = Hashtbl.find_opt cst v in
  let fold (v, instr) =
    (* forward pass: record literals, then fold an op whose operands are all known constants *)
    (match instr with
    | Sil.Int_lit n -> Hashtbl.replace cst v (CInt n)
    | Sil.Bool_lit b -> Hashtbl.replace cst v (CBool b)
    | _ -> ());
    match instr with
    | Sil.Binop (op, a, b) -> (
        match (get a, get b) with
        | Some ca, Some cb -> (
            match fold_binop op ca cb with Some c -> Hashtbl.replace cst v c; (v, cst_to_instr c) | None -> (v, instr))
        | _ -> (v, instr))
    | Sil.Unop (op, a) -> (
        match get a with
        | Some ca -> ( match fold_unop op ca with Some c -> Hashtbl.replace cst v c; (v, cst_to_instr c) | None -> (v, instr))
        | None -> (v, instr))
    | _ -> (v, instr)
  in
  (* blocks in execution order, instrs in program order (a definition is seen before its uses) *)
  List.iter
    (fun (b : Sil.block) -> b.Sil.instrs <- List.rev_map fold (List.rev b.Sil.instrs))
    (List.rev f.Sil.blocks);
  f

(* ---- pass: dead-instruction elimination (remove pure instrs whose result is never used) ---- *)
let dead_instr_elim (f : Sil.func) : Sil.func =
  let used : (Sil.value, unit) Hashtbl.t = Hashtbl.create 64 in
  let mark v = Hashtbl.replace used v () in
  List.iter
    (fun (b : Sil.block) ->
      List.iter (fun (_, instr) -> List.iter mark (operands instr)) b.Sil.instrs;
      List.iter mark (term_operands b.Sil.term))
    f.Sil.blocks;
  let keep (v, instr) = Hashtbl.mem used v || has_side_effect instr in
  List.iter (fun (b : Sil.block) -> b.Sil.instrs <- List.filter keep b.Sil.instrs) f.Sil.blocks;
  f

(* ================= concept 16: mem2reg — promote stack slots to SSA ================= *)
module IMap = Map.Make (Int)
module ISet = Set.Make (Int)

(* the SSA value an operand may be rewritten to / from (used to map old values to new) *)
let map_instr (g : Sil.value -> Sil.value) : Sil.instr -> Sil.instr = function
  | Sil.Load a -> Sil.Load (g a)
  | Sil.Store (x, a) -> Sil.Store (g x, g a)
  | Sil.Binop (op, a, b) -> Sil.Binop (op, g a, g b)
  | Sil.Unop (op, a) -> Sil.Unop (op, g a)
  | Sil.Apply (fr, args) -> Sil.Apply (g fr, List.map g args)
  | Sil.Print a -> Sil.Print (g a)
  | Sil.Struct fs -> Sil.Struct (List.map g fs)
  | Sil.Struct_extract (a, i) -> Sil.Struct_extract (g a, i)
  | Sil.Struct_element_addr (a, i) -> Sil.Struct_element_addr (g a, i)
  | Sil.Enum (t, p) -> Sil.Enum (t, List.map g p)
  | Sil.Enum_tag a -> Sil.Enum_tag (g a)
  | Sil.Enum_payload (a, i) -> Sil.Enum_payload (g a, i)
  | other -> other

let map_term (g : Sil.value -> Sil.value) : Sil.term -> Sil.term = function
  | Sil.Br (n, args) -> Sil.Br (n, List.map g args)
  | Sil.Cond_br (c, (t, ta), (e, ea)) -> Sil.Cond_br (g c, (t, List.map g ta), (e, List.map g ea))
  | Sil.Return (Some v) -> Sil.Return (Some (g v))
  | other -> other

let succs (b : Sil.block) : int list =
  match b.Sil.term with Sil.Br (n, _) -> [ n ] | Sil.Cond_br (_, (t, _), (e, _)) -> [ t; e ] | _ -> []

let mem2reg (f : Sil.func) : Sil.func =
  let blocks = List.rev f.Sil.blocks in (* entry (bb0) first *)
  let ids = List.map (fun (b : Sil.block) -> b.Sil.bid) blocks in
  let block : (int, Sil.block) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun (b : Sil.block) -> Hashtbl.replace block b.Sil.bid b) blocks;
  let blk n = Hashtbl.find block n in
  (* predecessors *)
  let preds : (int, int list) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun (b : Sil.block) ->
      List.iter (fun s -> Hashtbl.replace preds s (b.Sil.bid :: (try Hashtbl.find preds s with Not_found -> []))) (succs b))
    blocks;
  let pred n = try Hashtbl.find preds n with Not_found -> [] in

  (* (1) promotable slots: an alloc_stack whose value is only ever a load/store ADDRESS *)
  let value_uses : Sil.instr -> Sil.value list = function
    | Sil.Load _ -> [] (* the address is not a value use *)
    | Sil.Store (x, _) -> [ x ] (* the stored value, not the slot address *)
    | other -> operands other
  in
  let value_used : (Sil.value, unit) Hashtbl.t = Hashtbl.create 64 in
  List.iter
    (fun (b : Sil.block) ->
      List.iter (fun (_, i) -> List.iter (fun v -> Hashtbl.replace value_used v ()) (value_uses i)) b.Sil.instrs;
      List.iter (fun v -> Hashtbl.replace value_used v ()) (term_operands b.Sil.term))
    blocks;
  let slot_ty : (Sil.value, Types.ty) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun (b : Sil.block) ->
      List.iter (fun (v, i) -> match i with Sil.Alloc_stack _ when not (Hashtbl.mem value_used v) -> Hashtbl.replace slot_ty v (Hashtbl.find f.Sil.val_ty v) | _ -> ()) b.Sil.instrs)
    blocks;
  let is_promo s = Hashtbl.mem slot_ty s in
  if Hashtbl.length slot_ty = 0 then f
  else begin
    (* (2) dominators (iterative dataflow) + idom *)
    let entry = List.hd ids in
    let all = ISet.of_list ids in
    let dom : (int, ISet.t) Hashtbl.t = Hashtbl.create 16 in
    List.iter (fun n -> Hashtbl.replace dom n (if n = entry then ISet.singleton entry else all)) ids;
    let changed = ref true in
    while !changed do
      changed := false;
      List.iter
        (fun n ->
          if n <> entry then begin
            let inter = List.fold_left (fun acc p -> ISet.inter acc (Hashtbl.find dom p)) all (pred n) in
            let nd = ISet.add n inter in
            if not (ISet.equal nd (Hashtbl.find dom n)) then (Hashtbl.replace dom n nd; changed := true)
          end)
        ids
    done;
    let idom : (int, int) Hashtbl.t = Hashtbl.create 16 in
    List.iter
      (fun n ->
        if n <> entry then
          let strict = ISet.remove n (Hashtbl.find dom n) in
          (* the deepest strict dominator: the d dominated by every other strict dominator *)
          let best = ISet.fold (fun d acc -> match acc with None -> Some d | Some b -> if ISet.mem b (Hashtbl.find dom d) then Some d else acc) strict None in
          Option.iter (fun d -> Hashtbl.replace idom n d) best)
      ids;
    let id_of n = try Some (Hashtbl.find idom n) with Not_found -> None in

    (* (3) dominance frontiers (Cooper–Harvey–Kennedy) *)
    let df : (int, ISet.t) Hashtbl.t = Hashtbl.create 16 in
    let add_df b w = Hashtbl.replace df b (ISet.add w (try Hashtbl.find df b with Not_found -> ISet.empty)) in
    List.iter
      (fun w ->
        let ps = pred w in
        if List.length ps >= 2 then
          List.iter
            (fun p ->
              let runner = ref (Some p) in
              while !runner <> None && !runner <> id_of w do
                (match !runner with Some r -> add_df r w | None -> ());
                runner := (match !runner with Some r -> id_of r | None -> None)
              done)
            ps)
      ids;
    let frontier b = try Hashtbl.find df b with Not_found -> ISet.empty in

    (* (3b) per-slot LIVENESS (backward dataflow), so we place phis only where a slot is live —
       "pruned SSA". gen = slots loaded before being stored in a block; kill = slots stored. *)
    let gen = Hashtbl.create 16 and kill = Hashtbl.create 16 in
    List.iter
      (fun (b : Sil.block) ->
        let g = ref ISet.empty and k = ref ISet.empty in
        List.iter
          (fun (_, i) ->
            match i with
            | Sil.Load a when is_promo a -> if not (ISet.mem a !k) then g := ISet.add a !g
            | Sil.Store (_, a) when is_promo a -> k := ISet.add a !k
            | _ -> ())
          (List.rev b.Sil.instrs);
        Hashtbl.replace gen b.Sil.bid !g;
        Hashtbl.replace kill b.Sil.bid !k)
      blocks;
    let live_in = Hashtbl.create 16 in
    List.iter (fun n -> Hashtbl.replace live_in n ISet.empty) ids;
    let lchanged = ref true in
    while !lchanged do
      lchanged := false;
      List.iter
        (fun n ->
          let live_out = List.fold_left (fun acc s -> ISet.union acc (Hashtbl.find live_in s)) ISet.empty (succs (blk n)) in
          let ni = ISet.union (Hashtbl.find gen n) (ISet.diff live_out (Hashtbl.find kill n)) in
          if not (ISet.equal ni (Hashtbl.find live_in n)) then (Hashtbl.replace live_in n ni; lchanged := true))
        (List.rev ids)
    done;
    let live n s = ISet.mem s (Hashtbl.find live_in n) in

    (* (4) place a block argument (phi) for each slot at the iterated dominance frontier of its
       store-blocks — but only where the slot is LIVE. arg_slot records which slot an arg stands for. *)
    let arg_slot : (Sil.value, Sil.value) Hashtbl.t = Hashtbl.create 16 in (* block-arg value -> slot *)
    let phi_at : (int * Sil.value, Sil.value) Hashtbl.t = Hashtbl.create 16 in (* (block, slot) -> arg value *)
    let next = ref (1 + List.fold_left (fun m (b : Sil.block) -> List.fold_left (fun m (v, _) -> max m v) (List.fold_left (fun m (v, _) -> max m v) m b.Sil.args) b.Sil.instrs) (List.fold_left (fun m (v, _) -> max m v) 0 f.Sil.params) blocks) in
    let fresh ty = let v = !next in incr next; Hashtbl.replace f.Sil.val_ty v ty; v in
    ignore phi_at;
    Hashtbl.iter
      (fun slot ty ->
        let defs = List.filter_map (fun (b : Sil.block) -> if List.exists (fun (_, i) -> match i with Sil.Store (_, a) -> a = slot | _ -> false) b.Sil.instrs then Some b.Sil.bid else None) blocks in
        (* iterated dominance frontier of the def-blocks = candidate phi blocks *)
        let worklist = ref defs and seen = ref ISet.empty and phi_blocks = ref ISet.empty in
        while !worklist <> [] do
          let d = List.hd !worklist in
          worklist := List.tl !worklist;
          ISet.iter
            (fun w ->
              if not (ISet.mem w !seen) then begin
                seen := ISet.add w !seen;
                phi_blocks := ISet.add w !phi_blocks;
                if not (List.mem w defs) then worklist := w :: !worklist
              end)
            (frontier d)
        done;
        (* place a block argument only where the slot is actually LIVE (pruned SSA) — so a phi is
           never created for a variable that isn't live across the join (which would have no
           reaching value on some incoming edge) *)
        ISet.iter
          (fun w ->
            if live w slot then begin
              let av = fresh ty in
              let wb = blk w in
              wb.Sil.args <- wb.Sil.args @ [ (av, ty) ];
              Hashtbl.replace arg_slot av slot;
              Hashtbl.replace phi_at (w, slot) av
            end)
          !phi_blocks)
      slot_ty;

    (* (5) rename: a dominator-tree DFS threading each slot's reaching value. Build `replace`
       (load result -> reaching value), mark loads/stores for removal, and fill branch arguments. *)
    let dom_children : (int, int list) Hashtbl.t = Hashtbl.create 16 in
    List.iter (fun n -> match id_of n with Some d -> Hashtbl.replace dom_children d (n :: (try Hashtbl.find dom_children d with Not_found -> [])) | None -> ()) ids;
    let children n = try Hashtbl.find dom_children n with Not_found -> [] in
    let replace : (Sil.value, Sil.value) Hashtbl.t = Hashtbl.create 64 in
    let removed : (Sil.value, unit) Hashtbl.t = Hashtbl.create 64 in
    let rec rename n (cur : Sil.value IMap.t) =
      let b = blk n in
      (* incoming phis define the slot on entry *)
      let cur = List.fold_left (fun c (av, _) -> match Hashtbl.find_opt arg_slot av with Some s -> IMap.add s av c | None -> c) cur b.Sil.args in
      let cur = ref cur in
      List.iter
        (fun (v, i) ->
          match i with
          | Sil.Store (x, a) when is_promo a -> cur := IMap.add a x !cur; Hashtbl.replace removed v ()
          | Sil.Load a when is_promo a -> Hashtbl.replace replace v (IMap.find a !cur); Hashtbl.replace removed v ()
          | _ -> ())
        (List.rev b.Sil.instrs);
      (* fill this block's branch arguments for each successor's phis *)
      let arg_list_for s = List.map (fun (av, _) -> match Hashtbl.find_opt arg_slot av with Some sl -> IMap.find sl !cur | None -> av) (blk s).Sil.args in
      b.Sil.term <-
        (match b.Sil.term with
        | Sil.Br (s, _) -> Sil.Br (s, arg_list_for s)
        | Sil.Cond_br (c, (t, _), (e, _)) -> Sil.Cond_br (c, (t, arg_list_for t), (e, arg_list_for e))
        | other -> other);
      List.iter (fun child -> rename child !cur) (children n)
    in
    rename entry IMap.empty;

    (* (6) commit: drop promoted allocas + their loads/stores, then rewrite remaining operands
       (chasing the replace map to the reaching SSA value). *)
    let rec resolve v = match Hashtbl.find_opt replace v with Some v' when v' <> v -> resolve v' | _ -> v in
    List.iter
      (fun (b : Sil.block) ->
        b.Sil.instrs <-
          List.filter_map
            (fun (v, i) ->
              if Hashtbl.mem removed v then None
              else match i with Sil.Alloc_stack _ when is_promo v -> None | _ -> Some (v, map_instr resolve i))
            b.Sil.instrs;
        b.Sil.term <- map_term resolve b.Sil.term)
      blocks;
    f
  end

(* ---- pass: simplify the CFG (concept 17) — fold a branch on a constant condition, then delete
   blocks that are no longer reachable from the entry ---- *)
let simplify_cfg (f : Sil.func) : Sil.func =
  (* TODO(17): two steps.
     (a) BRANCH FOLDING. Collect the values that are known Bool constants (the `Sil.Bool_lit`
         instructions). For each block whose terminator is `Sil.Cond_br (c, (t, ta), (e, ea))` where
         `c` is a known constant, replace it with `Sil.Br (t, ta)` if the constant is true, else
         `Sil.Br (e, ea)` — keeping the taken side's branch arguments.
     (b) DEAD-BLOCK ELIMINATION. Compute the blocks reachable from the entry (bb0) by a DFS over
         `succs`, then set `f.Sil.blocks` to only the reachable ones. (Removing a now-unreachable
         block also removes its branches, so target phis lose the stale incoming automatically.) *)
  ignore succs;
  f

(* ---- the default `-O` pipeline. mem2reg first (so the rest see through memory), then
   fold/simplify/clean — repeated once so a folded branch exposes more folding. ---- *)
let default_pipeline =
  [
    { name = "mem2reg"; run = mem2reg };
    { name = "constant-fold"; run = constant_fold };
    { name = "simplify-cfg"; run = simplify_cfg };
    { name = "constant-fold"; run = constant_fold };
    { name = "simplify-cfg"; run = simplify_cfg };
    { name = "dead-instr-elim"; run = dead_instr_elim };
  ]

let optimize ?(log = false) (m : Sil.modul) : Sil.modul = run_pipeline ~log default_pipeline m
