(* FROZEN SOLUTION — concept 19 optimizer: inlining (single-block leaves) + mem2reg/fold/cfg/GVN/DCE. *)

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
  match (a, b) with
  | CInt x, CInt y -> (
      match op with
      | Ast.Add -> Some (CInt (x + y)) | Ast.Sub -> Some (CInt (x - y)) | Ast.Mul -> Some (CInt (x * y))
      | Ast.Div -> if y = 0 then None else Some (CInt (x / y)) (* leave ÷0/%0 for the runtime trap *)
      | Ast.Mod -> if y = 0 then None else Some (CInt (x mod y))
      | Ast.Eq -> Some (CBool (x = y)) | Ast.Ne -> Some (CBool (x <> y))
      | Ast.Lt -> Some (CBool (x < y)) | Ast.Le -> Some (CBool (x <= y))
      | Ast.Gt -> Some (CBool (x > y)) | Ast.Ge -> Some (CBool (x >= y))
      | Ast.And | Ast.Or -> None)
  | CBool p, CBool q -> (
      match op with
      | Ast.Eq -> Some (CBool (p = q)) | Ast.Ne -> Some (CBool (p <> q))
      | Ast.And -> Some (CBool (p && q)) | Ast.Or -> Some (CBool (p || q))
      | _ -> None)
  | _ -> None

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
  (* which values are known Bool constants *)
  let bcst : (Sil.value, bool) Hashtbl.t = Hashtbl.create 64 in
  List.iter
    (fun (b : Sil.block) -> List.iter (fun (v, i) -> match i with Sil.Bool_lit x -> Hashtbl.replace bcst v x | _ -> ()) b.Sil.instrs)
    f.Sil.blocks;
  (* (a) a cond_br on a constant becomes an unconditional br to the taken side (keeping its args) *)
  List.iter
    (fun (b : Sil.block) ->
      match b.Sil.term with
      | Sil.Cond_br (c, (t, ta), (e, ea)) -> (
          match Hashtbl.find_opt bcst c with
          | Some true -> b.Sil.term <- Sil.Br (t, ta)
          | Some false -> b.Sil.term <- Sil.Br (e, ea)
          | None -> ())
      | _ -> ())
    f.Sil.blocks;
  (* (b) keep only blocks reachable from the entry (bb0) *)
  let by_id : (int, Sil.block) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun (b : Sil.block) -> Hashtbl.replace by_id b.Sil.bid b) f.Sil.blocks;
  let reach : (int, unit) Hashtbl.t = Hashtbl.create 16 in
  let rec dfs n =
    if not (Hashtbl.mem reach n) then begin
      Hashtbl.replace reach n ();
      match Hashtbl.find_opt by_id n with Some b -> List.iter dfs (succs b) | None -> ()
    end
  in
  dfs 0;
  f.Sil.blocks <- List.filter (fun (b : Sil.block) -> Hashtbl.mem reach b.Sil.bid) f.Sil.blocks;
  f

(* ================= concept 18: GVN — global value numbering / CSE ================= *)

(* a stable string KEY identifying what a PURE instruction computes — equal keys ⇒ equal values.
   Operands are run through `canon` first so we compare canonical (already-numbered) values.
   Impure/unique instructions (load/store/apply/print/alloc_stack) return None — never CSE'd. *)
(* the result TYPE is part of the key: `struct (%1) $A` and `struct (%1) $B` are equal
   field-for-field but are NOT the same value — merging them once produced ill-typed LLVM
   (caught by concept 21's empty conformer structs; latent for any two same-shaped structs). *)
let value_key (canon : Sil.value -> Sil.value) (rty : Types.ty) : Sil.instr -> string option =
  let v x = string_of_int (canon x) in
  let t () = Types.string_of_ty rty in
  function
  | Sil.Int_lit n -> Some (Printf.sprintf "int:%d" n)
  | Sil.Bool_lit b -> Some (Printf.sprintf "bool:%b" b)
  | Sil.Float_lit f -> Some (Printf.sprintf "float:%h" f)
  | Sil.String_lit s -> Some (Printf.sprintf "str:%S" s)
  | Sil.Func_ref n -> Some (Printf.sprintf "fref:%s" n)
  | Sil.Binop (op, a, b) -> Some (Printf.sprintf "bin:%s:%s:%s" (Ast.string_of_binop op) (v a) (v b))
  | Sil.Unop (op, a) -> Some (Printf.sprintf "un:%s:%s" (Ast.string_of_unop op) (v a))
  | Sil.Struct fs -> Some (Printf.sprintf "struct:%s:%s" (t ()) (String.concat "," (List.map v fs)))
  | Sil.Struct_extract (a, i) -> Some (Printf.sprintf "sext:%s:%d" (v a) i)
  | Sil.Enum (tg, p) -> Some (Printf.sprintf "enum:%s:%d:%s" (t ()) tg (String.concat "," (List.map v p)))
  | Sil.Enum_tag a -> Some (Printf.sprintf "etag:%s" (v a))
  | Sil.Enum_payload (a, i) -> Some (Printf.sprintf "epay:%s:%d" (v a) i)
  | Sil.Load _ | Sil.Store _ | Sil.Apply _ | Sil.Print _ | Sil.Alloc_stack _ | Sil.Struct_element_addr _ -> None

let gvn (f : Sil.func) : Sil.func =
  let blocks = List.rev f.Sil.blocks in (* entry first *)
  let ids = List.map (fun (b : Sil.block) -> b.Sil.bid) blocks in
  let block : (int, Sil.block) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun (b : Sil.block) -> Hashtbl.replace block b.Sil.bid b) blocks;
  let blk n = Hashtbl.find block n in
  let preds : (int, int list) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun (b : Sil.block) -> List.iter (fun s -> Hashtbl.replace preds s (b.Sil.bid :: (try Hashtbl.find preds s with Not_found -> []))) (succs b)) blocks;
  let pred n = try Hashtbl.find preds n with Not_found -> [] in
  (* dominator tree (same iterative dataflow as mem2reg) *)
  let entry = List.hd ids and all = ISet.of_list ids in
  let dom = Hashtbl.create 16 in
  List.iter (fun n -> Hashtbl.replace dom n (if n = entry then ISet.singleton entry else all)) ids;
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter (fun n -> if n <> entry then begin
      let inter = List.fold_left (fun acc p -> ISet.inter acc (Hashtbl.find dom p)) all (pred n) in
      let nd = ISet.add n inter in
      if not (ISet.equal nd (Hashtbl.find dom n)) then (Hashtbl.replace dom n nd; changed := true) end) ids
  done;
  let children = Hashtbl.create 16 in
  List.iter (fun n -> if n <> entry then begin
    let strict = ISet.remove n (Hashtbl.find dom n) in
    let best = ISet.fold (fun d acc -> match acc with None -> Some d | Some b -> if ISet.mem b (Hashtbl.find dom d) then Some d else acc) strict None in
    Option.iter (fun d -> Hashtbl.replace children d (n :: (try Hashtbl.find children d with Not_found -> []))) best end) ids;
  let kids n = try Hashtbl.find children n with Not_found -> [] in
  (* the value-numbering DFS: a scoped table `key -> canonical value`, valid in the dominance
     scope. A pure instruction whose key is already in scope is REDUNDANT -> redirect its uses. *)
  let table : (string, Sil.value) Hashtbl.t = Hashtbl.create 64 in
  let repl : (Sil.value, Sil.value) Hashtbl.t = Hashtbl.create 64 in
  let removed : (Sil.value, unit) Hashtbl.t = Hashtbl.create 64 in
  let rec canon v = match Hashtbl.find_opt repl v with Some v' when v' <> v -> canon v' | _ -> v in
  let rec visit n =
    let added = ref [] in
    List.iter
      (fun (v, instr) ->
        match value_key canon (Hashtbl.find f.Sil.val_ty v) instr with
        | None -> ()
        | Some k -> (
            match Hashtbl.find_opt table k with
            | Some existing -> Hashtbl.replace repl v existing; Hashtbl.replace removed v ()
            | None -> Hashtbl.replace table k v; added := k :: !added))
      (List.rev (blk n).Sil.instrs);
    List.iter visit (kids n);
    List.iter (fun k -> Hashtbl.remove table k) !added (* leave the scope *)
  in
  visit entry;
  (* drop the redundant instructions and rewrite all operands to their canonical value *)
  List.iter
    (fun (b : Sil.block) ->
      b.Sil.instrs <- List.filter_map (fun (v, i) -> if Hashtbl.mem removed v then None else Some (v, map_instr canon i)) b.Sil.instrs;
      b.Sil.term <- map_term canon b.Sil.term)
    blocks;
  f

(* ================= concept 19: function inlining (inter-procedural) ================= *)

(* v0 inlines a call only when the callee is a SINGLE-BLOCK LEAF (exactly one block, no `apply`
   inside, not `main`): no recursion, no block surgery — splice its instructions at the call site.
   Multi-block callees (with internal control flow) are a v1/exercise. *)
let inlinable (f : Sil.func) : bool =
  f.Sil.fname <> "main"
  && (match f.Sil.blocks with
     | [ b ] -> not (List.exists (fun (_, i) -> match i with Sil.Apply _ -> true | _ -> false) b.Sil.instrs)
     | _ -> false)

let inline_module (m : Sil.modul) : Sil.modul =
  let by_name : (string, Sil.func) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun (f : Sil.func) -> Hashtbl.replace by_name f.Sil.fname f) m.Sil.funcs;
  let callee n = match Hashtbl.find_opt by_name n with Some f when inlinable f -> Some f | _ -> None in
  let max_val (g : Sil.func) =
    let m0 = List.fold_left (fun m (v, _) -> max m v) 0 g.Sil.params in
    List.fold_left (fun m (b : Sil.block) ->
      List.fold_left (fun m (v, _) -> max m v) (List.fold_left (fun m (v, _) -> max m v) m b.Sil.args) b.Sil.instrs)
      m0 g.Sil.blocks
  in
  let inline_in (g : Sil.func) =
    let progress = ref true in
    while !progress do
      progress := false;
      (* func_ref value -> name, so we can resolve an apply's target *)
      let fref = Hashtbl.create 16 in
      List.iter (fun (b : Sil.block) -> List.iter (fun (v, i) -> match i with Sil.Func_ref n -> Hashtbl.replace fref v n | _ -> ()) b.Sil.instrs) g.Sil.blocks;
      (* find the first inlinable call *)
      let found = ref None in
      List.iter
        (fun (b : Sil.block) ->
          List.iter
            (fun (rv, i) ->
              match i with
              | Sil.Apply (fr, args) when !found = None -> (
                  match Option.bind (Hashtbl.find_opt fref fr) callee with Some f -> found := Some (b, rv, args, f) | None -> ())
              | _ -> ())
            (List.rev b.Sil.instrs))
        g.Sil.blocks;
      match !found with
      | None -> ()
      | Some (b, rv, args, f) ->
          progress := true;
          let off = max_val g + 1 in
          let fb = match f.Sil.blocks with [ b ] -> b | _ -> assert false in
          (* a callee value maps: a parameter -> its actual argument; anything else -> shifted by off *)
          let param_arg = List.map2 (fun (p, _) a -> (p, a)) f.Sil.params args in
          let vmap v = match List.assoc_opt v param_arg with Some a -> a | None -> v + off in
          (* the callee's instructions, renumbered, carrying their types into the caller *)
          let inlined =
            List.map
              (fun (v, i) -> Hashtbl.replace g.Sil.val_ty (vmap v) (Hashtbl.find f.Sil.val_ty v); (vmap v, map_instr vmap i))
              (List.rev fb.Sil.instrs)
          in
          let retval = match fb.Sil.term with Sil.Return (Some v) -> Some (vmap v) | Sil.Return None -> None | _ -> assert false in
          (* splice the inlined instructions in place of the call *)
          let rec splice = function
            | (v, _) :: rest when v = rv -> inlined @ rest
            | x :: rest -> x :: splice rest
            | [] -> []
          in
          b.Sil.instrs <- List.rev (splice (List.rev b.Sil.instrs));
          (* the call result becomes the callee's return value everywhere *)
          (match retval with
          | Some rv' ->
              let sub x = if x = rv then rv' else x in
              List.iter (fun (bb : Sil.block) -> bb.Sil.instrs <- List.map (fun (v, i) -> (v, map_instr sub i)) bb.Sil.instrs; bb.Sil.term <- map_term sub bb.Sil.term) g.Sil.blocks
          | None -> ())
    done
  in
  List.iter inline_in m.Sil.funcs;
  (* drop functions that are no longer CALLED — count only `apply`s (a dead func_ref left over from
     inlining doesn't count), so a fully-inlined callee is removed *)
  let called = Hashtbl.create 16 in
  List.iter
    (fun (f : Sil.func) ->
      let fref = Hashtbl.create 16 in
      List.iter (fun (b : Sil.block) -> List.iter (fun (v, i) -> match i with Sil.Func_ref n -> Hashtbl.replace fref v n | _ -> ()) b.Sil.instrs) f.Sil.blocks;
      List.iter (fun (b : Sil.block) -> List.iter (fun (_, i) -> match i with Sil.Apply (fr, _) -> Option.iter (fun n -> Hashtbl.replace called n ()) (Hashtbl.find_opt fref fr) | _ -> ()) b.Sil.instrs) f.Sil.blocks)
    m.Sil.funcs;
  { m with Sil.funcs = List.filter (fun (f : Sil.func) -> f.Sil.fname = "main" || Hashtbl.mem called f.Sil.fname) m.Sil.funcs }

(* ---- the default `-O` pipeline. INLINE first (inter-procedural), then per-function: mem2reg,
   fold/simplify/GVN/clean — so the passes run across the old call boundary. ---- *)
let default_pipeline =
  [
    { name = "mem2reg"; run = mem2reg };
    { name = "constant-fold"; run = constant_fold };
    { name = "simplify-cfg"; run = simplify_cfg };
    { name = "constant-fold"; run = constant_fold };
    { name = "gvn"; run = gvn };
    { name = "simplify-cfg"; run = simplify_cfg };
    { name = "dead-instr-elim"; run = dead_instr_elim };
  ]

let optimize ?(log = false) (m : Sil.modul) : Sil.modul = run_pipeline ~log default_pipeline (inline_module m)
