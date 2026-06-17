(* peephole.ml — peephole / local redundancy elimination + a (light) scheduler (concept 36).

   After register allocation, the memory-based SIL we lower leaves a flood of low-level redundancy
   that the SIL-level passes (Phase 4) could never see, because it only exists as concrete
   register/memory traffic: a value stored to a slot and then loaded straight back, the same slot
   loaded twice, a move to self. A PEEPHOLE pass cleans these up by sliding over the final stream.

   The core is LOCAL REDUNDANT-LOAD ELIMINATION within a basic block: track which register currently
   holds each memory slot's value, and turn a reload of that slot into a register MOVE (or delete it
   when the same register already holds it). It's safe as long as we INVALIDATE the bookkeeping
   whenever a tracked register is overwritten, a slot is restored, or a call clobbers state. A move
   to self is then dead and is dropped.

   Honest scope: this removes LOCAL (within-block) redundancy. The dominant cost in our code — a
   variable reloaded at the top of every block because it lives in alloc_stack memory — is
   CROSS-block, and removing that needs mem2reg/SSA promotion (concept 34's exercise), not a
   peephole. Knowing which pass removes which redundancy is the lesson. *)

let mem_key (b : Arm64.reg) (o : int) = (b, o)

(* invalidate every slot whose current holder is [r] (it was just overwritten) *)
let kill_reg (held : (Arm64.reg * int, Arm64.reg) Hashtbl.t) (r : Arm64.reg) : unit =
  let stale = Hashtbl.fold (fun k v acc -> if v = r then k :: acc else acc) held [] in
  List.iter (Hashtbl.remove held) stale

(* ===== the learner's hole: TODO(36) local redundant-load elimination within one block ===== *)

(* rewrite one basic block. `held` maps a memory slot (base,offset) to the register that currently
   holds its value; `changed` records whether anything was rewritten. *)
let rewrite_block (changed : bool ref) (instrs : Arm64.instr list) : Arm64.instr list =
  let held : (Arm64.reg * int, Arm64.reg) Hashtbl.t = Hashtbl.create 16 in
  let out = ref [] in
  let emit i = out := i :: !out in
  List.iter
    (fun (i : Arm64.instr) ->
      match i with
      | Arm64.Str (rs, b, o) ->
          (* a store writes MEMORY, not a register: rs is unchanged, and distinct stack slots don't
             alias, so nothing is invalidated. The store stays (memory must be written), and now
             slot (b,o) is held by rs — a later reload of (b,o) can become `mov …, rs`. *)
          emit i;
          Hashtbl.replace held (mem_key b o) rs
      | Arm64.Ldr (rd, b, o) -> (
          (match Hashtbl.find_opt held (mem_key b o) with
          | Some rsrc when rsrc = rd -> changed := true (* already in rd — drop the load *)
          | Some rsrc -> changed := true; kill_reg held rd; emit (Arm64.Mov (rd, Arm64.R rsrc))
          | None -> kill_reg held rd; emit i);
          (* after the load, rd holds slot (b,o)'s value *)
          Hashtbl.replace held (mem_key b o) rd)
      | Arm64.Mov (rd, Arm64.R rs) when rd = rs -> changed := true (* move to self: drop *)
      | other ->
          (* every register this instruction writes is no longer a faithful copy of its old slot *)
          let _, writes = Arm64.reads_writes other in
          List.iter (kill_reg held) writes;
          (match other with Arm64.Bl _ -> Hashtbl.reset held | _ -> ());
          emit other)
    instrs;
  List.rev !out

(* ===== given: split into blocks, drive to a fixpoint, the (honest) scheduler ===== *)

(* split a flat instruction list into basic blocks at labels and after branches/returns *)
let blocks_of (instrs : Arm64.instr list) : Arm64.instr list list =
  let rec go cur acc = function
    | [] -> List.rev (if cur = [] then acc else List.rev cur :: acc)
    | (Arm64.Label _ as l) :: rest ->
        (* a label starts a new block *)
        let acc = if cur = [] then acc else List.rev cur :: acc in
        go [ l ] acc rest
    | ((Arm64.B _ | Arm64.Bcond _ | Arm64.Bl _ | Arm64.Ret | Arm64.Brk _) as t) :: rest ->
        go [] (List.rev (t :: cur) :: acc) rest
    | i :: rest -> go (i :: cur) acc rest
  in
  go [] [] instrs

let peephole (instrs : Arm64.instr list) : Arm64.instr list =
  let one instrs =
    let changed = ref false in
    let bs = List.map (rewrite_block changed) (blocks_of instrs) in
    (List.concat bs, !changed)
  in
  let rec fix instrs = let instrs', ch = one instrs in if ch then fix instrs' else instrs' in
  fix instrs

(* A basic-block LIST SCHEDULER (given, deliberately the identity). It would reorder independent
   instructions to separate a producer from its consumer (latency hiding). On an in-order core that
   matters; on Apple's OUT-OF-ORDER cores the hardware reorders anyway, so the measured benefit is
   ~nil — the honest lesson is that PEEPHOLE (fewer instructions) beats SCHEDULING (same
   instructions, reordered) on modern hardware. A real dependence-DAG list scheduler is the
   exercise. *)
let schedule (instrs : Arm64.instr list) : Arm64.instr list = instrs

let optimize (f : Arm64.func) : Arm64.func =
  { f with Arm64.instrs = schedule (peephole f.Arm64.instrs) }
