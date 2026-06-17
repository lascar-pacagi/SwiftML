(* regalloc.ml — register allocation: map virtual registers to physical ones (concept 34).

   The ladder (each rung runnable, each beats the last):
     v0 STACK         — spill every vreg to its frame slot (≈ concept 33). Correct, slow.
     v1 LINEAR-SCAN   — assign over live intervals; spill the interval ending latest under pressure.
     v2 GRAPH-COLOUR  — interference graph + simplify/spill/select (Chaitin–Briggs).

   The allocatable pool is the CALLEE-SAVED registers x19..x27 — values placed there survive a `bl`
   for free (the callee preserves them), so we never have to model call-clobbered registers. x9..x14
   are reserved scratch for the spill rewrite; x0..x7 carry call args/results (handled by isel). A
   "spill" of vreg v just means "live in its slot [sp, #16 + 8*v]" — every vreg already has a home. *)

let round16 n = (n + 15) / 16 * 16
let pool = [ 19; 20; 21; 22; 23; 24; 25; 26; 27 ] (* allocatable callee-saved registers *)
let k = List.length pool
let scratch = [ 9; 10; 11; 12; 13; 14 ] (* reserved for loading/storing spilled operands *)

type loc = Reg of int | Spill (* a physical register, or "live in your own frame slot" *)
type strategy = Stack | Linscan | Graphcolor

let slot_of v = 16 + (8 * v)
let vnum = function Arm64.Virt n -> Some n | _ -> None

(* === apply a register substitution to every register operand of an instruction === *)
let map_regs (g : Arm64.reg -> Arm64.reg) (i : Arm64.instr) : Arm64.instr =
  let open Arm64 in
  let mo = function R r -> R (g r) | Imm n -> Imm n in
  match i with
  | Mov (d, o) -> Mov (g d, mo o)
  | Movz (d, a, b) -> Movz (g d, a, b)
  | Movk (d, a, b) -> Movk (g d, a, b)
  | Add (d, a, o) -> Add (g d, g a, mo o)
  | Sub (d, a, o) -> Sub (g d, g a, mo o)
  | Mul (d, a, b) -> Mul (g d, g a, g b)
  | Sdiv (d, a, b) -> Sdiv (g d, g a, g b)
  | Msub (d, n, m, a) -> Msub (g d, g n, g m, g a)
  | Neg (d, a) -> Neg (g d, g a)
  | And (d, a, o) -> And (g d, g a, mo o)
  | Orr (d, a, o) -> Orr (g d, g a, mo o)
  | Cmp (a, o) -> Cmp (g a, mo o)
  | Cset (d, c) -> Cset (g d, c)
  | Csel (d, t, f, c) -> Csel (g d, g t, g f, c)
  | Ldr (d, b, off) -> Ldr (g d, g b, off)
  | Str (s, b, off) -> Str (g s, g b, off)
  | Stp (a, b, base, off) -> Stp (g a, g b, g base, off)
  | Ldp (a, b, base, off) -> Ldp (g a, g b, g base, off)
  | Adrp (d, s) -> Adrp (g d, s)
  | AddSym (d, a, s) -> AddSym (g d, g a, s)
  | (B _ | Bcond _ | Bl _ | Brk _ | Ret | Label _ | Comment _) as x -> x

(* === control-flow successors of each instruction index (for liveness) === *)
let succs (instrs : Arm64.instr array) : int list array =
  let n = Array.length instrs in
  let label_idx = Hashtbl.create 16 in
  Array.iteri (fun i ins -> match ins with Arm64.Label l -> Hashtbl.replace label_idx l i | _ -> ()) instrs;
  let tgt l = try [ Hashtbl.find label_idx l ] with Not_found -> [] in
  Array.init n (fun i ->
      match instrs.(i) with
      | Arm64.B l -> tgt l
      | Arm64.Bcond (_, l) -> tgt l @ (if i + 1 < n then [ i + 1 ] else [])
      | Arm64.Ret | Arm64.Brk _ -> []
      | _ -> if i + 1 < n then [ i + 1 ] else [])

(* === liveness: live-in virtual registers at each instruction (backward dataflow to fixpoint) === *)
let liveness (instrs : Arm64.instr array) : (int, unit) Hashtbl.t array =
  let n = Array.length instrs in
  let sx = succs instrs in
  let vregs_of rs = List.filter_map vnum rs in
  let rds = Array.make n [] and wrs = Array.make n [] in
  Array.iteri
    (fun i ins -> let r, w = Arm64.reads_writes ins in rds.(i) <- vregs_of r; wrs.(i) <- vregs_of w)
    instrs;
  let live_in = Array.init n (fun _ -> Hashtbl.create 8) in
  let changed = ref true in
  while !changed do
    changed := false;
    for i = n - 1 downto 0 do
      (* out = union of successors' live_in *)
      let out = Hashtbl.create 8 in
      List.iter (fun s -> Hashtbl.iter (fun v () -> Hashtbl.replace out v ()) live_in.(s)) sx.(i);
      (* in = (out \ writes) ∪ reads *)
      let nin = Hashtbl.copy out in
      List.iter (fun v -> Hashtbl.remove nin v) wrs.(i);
      List.iter (fun v -> Hashtbl.replace nin v ()) rds.(i);
      if Hashtbl.length nin <> Hashtbl.length live_in.(i)
         || Hashtbl.fold (fun v () acc -> acc || not (Hashtbl.mem live_in.(i) v)) nin false
      then (live_in.(i) <- nin; changed := true)
    done
  done;
  live_in

(* a vreg's live interval [start, end] over the linear instruction order — covers loops because the
   underlying liveness reached a fixpoint over back-edges *)
let intervals (instrs : Arm64.instr array) (live_in : (int, unit) Hashtbl.t array) : (int * (int * int)) list =
  let n = Array.length instrs in
  let lo = Hashtbl.create 32 and hi = Hashtbl.create 32 in
  let touch v i =
    (match Hashtbl.find_opt lo v with Some x when x <= i -> () | _ -> Hashtbl.replace lo v i);
    (match Hashtbl.find_opt hi v with Some x when x >= i -> () | _ -> Hashtbl.replace hi v i)
  in
  for i = 0 to n - 1 do
    Hashtbl.iter (fun v () -> touch v i) live_in.(i);
    let r, w = Arm64.reads_writes instrs.(i) in
    List.iter (fun rr -> match vnum rr with Some v -> touch v i | None -> ()) (r @ w)
  done;
  Hashtbl.fold (fun v l acc -> (v, (l, Hashtbl.find hi v)) :: acc) lo []

(* ===================== the learner's holes ===================== *)

(* v1 — LINEAR SCAN (Poletto & Sarkar). Walk intervals in start order over a free pool of K
   registers; expire intervals whose end has passed; on pressure, spill whichever live interval
   ends LATEST (it frees its register for longer). *)
let linscan (instrs : Arm64.instr array) : (int, loc) Hashtbl.t =
  let assign = Hashtbl.create 32 in
  let live_in = liveness instrs in
  let ivs = List.sort (fun (_, (s1, _)) (_, (s2, _)) -> compare s1 s2) (intervals instrs live_in) in
  let free = ref pool in
  (* active = (vreg, end, reg), kept sorted by increasing end *)
  let active = ref [] in
  let expire start =
    let keep, gone = List.partition (fun (_, e, _) -> e >= start) !active in
    List.iter (fun (_, _, r) -> free := r :: !free) gone;
    active := keep
  in
  List.iter
    (fun (v, (s, e)) ->
      expire s;
      match !free with
      | r :: rest ->
          free := rest;
          Hashtbl.replace assign v (Reg r);
          active := List.sort (fun (_, e1, _) (_, e2, _) -> compare e1 e2) ((v, e, r) :: !active)
      | [] ->
          (* no register free: spill the interval (this one or an active one) ending latest *)
          let last = List.fold_left (fun acc x -> if (let (_, e, _) = x in e) > (let (_, e2, _) = acc in e2) then x else acc) (List.hd !active) (List.tl !active) in
          let lv, le, lr = last in
          if le > e then begin
            (* steal lr from the later-ending active interval; spill it instead *)
            Hashtbl.replace assign lv Spill;
            Hashtbl.replace assign v (Reg lr);
            active := List.sort (fun (_, e1, _) (_, e2, _) -> compare e1 e2)
                        ((v, e, lr) :: List.filter (fun (vv, _, _) -> vv <> lv) !active)
          end
          else Hashtbl.replace assign v Spill)
    ivs;
  assign

(* v2 — GRAPH COLOURING (Chaitin–Briggs). Build the interference graph (vregs whose intervals
   overlap interfere); SIMPLIFY (push degree<K nodes), spill the highest-degree node when stuck;
   then SELECT (pop, give each a colour none of its neighbours took, else actually spill). *)
let graphcolor (instrs : Arm64.instr array) : (int, loc) Hashtbl.t =
  let assign = Hashtbl.create 32 in
  let live_in = liveness instrs in
  let ivs = intervals instrs live_in in
  let nodes = List.map fst ivs in
  let span = Hashtbl.create 32 in
  List.iter (fun (v, se) -> Hashtbl.replace span v se) ivs;
  let overlap (s1, e1) (s2, e2) = s1 <= e2 && s2 <= e1 in
  (* adjacency sets *)
  let adj = Hashtbl.create 32 in
  List.iter (fun v -> Hashtbl.replace adj v (Hashtbl.create 8)) nodes;
  let rec pairs = function
    | [] | [ _ ] -> ()
    | a :: rest ->
        List.iter
          (fun b -> if overlap (Hashtbl.find span a) (Hashtbl.find span b) then (
               Hashtbl.replace (Hashtbl.find adj a) b ();
               Hashtbl.replace (Hashtbl.find adj b) a ()))
          rest;
        pairs rest
  in
  pairs nodes;
  let deg v removed = Hashtbl.fold (fun u () acc -> if Hashtbl.mem removed u then acc else acc + 1) (Hashtbl.find adj v) 0 in
  (* SIMPLIFY: repeatedly remove a node, preferring degree < K; push on a stack *)
  let removed = Hashtbl.create 32 and stack = ref [] in
  let remaining () = List.filter (fun v -> not (Hashtbl.mem removed v)) nodes in
  while remaining () <> [] do
    let rem = remaining () in
    let low = List.filter (fun v -> deg v removed < k) rem in
    let pick = match low with v :: _ -> v
      | [] -> List.fold_left (fun acc v -> if deg v removed > deg acc removed then v else acc) (List.hd rem) (List.tl rem)
    in
    Hashtbl.replace removed pick ();
    stack := pick :: !stack
  done;
  (* SELECT: pop, colour with a register no neighbour uses; if none, spill *)
  List.iter
    (fun v ->
      let used = Hashtbl.fold
          (fun u () acc -> match Hashtbl.find_opt assign u with Some (Reg r) -> r :: acc | _ -> acc)
          (Hashtbl.find adj v) [] in
      match List.filter (fun r -> not (List.mem r used)) pool with
      | r :: _ -> Hashtbl.replace assign v (Reg r)
      | [] -> Hashtbl.replace assign v Spill)
    !stack;
  assign

(* ===================== given machinery ===================== *)

(* v0 — STACK: spill everything (the baseline). *)
let stack_alloc (instrs : Arm64.instr array) : (int, loc) Hashtbl.t =
  let assign = Hashtbl.create 32 in
  Array.iter
    (fun ins ->
      let r, w = Arm64.reads_writes ins in
      List.iter (fun rr -> match vnum rr with Some n -> Hashtbl.replace assign n Spill | None -> ()) (r @ w))
    instrs;
  assign

(* rewrite each instruction: vregs in a register become that register; spilled vregs are loaded
   into scratch before the instruction and stored after it. Returns the physical instrs + the set
   of callee-saved registers actually used (for the prologue). *)
let rewrite (assign : (int, loc) Hashtbl.t) (instrs : Arm64.instr array) : Arm64.instr list * int list =
  let used_cs = Hashtbl.create 8 in
  let loc_of n = match Hashtbl.find_opt assign n with Some l -> l | None -> Spill in
  let out = ref [] in
  let push i = out := i :: !out in
  Array.iter
    (fun ins ->
      let reads, writes = Arm64.reads_writes ins in
      let spilled rs = List.sort_uniq compare (List.filter_map (fun r -> match vnum r with Some n when loc_of n = Spill -> Some n | _ -> None) rs) in
      let sreads = spilled reads and swrites = spilled writes in
      let all = List.sort_uniq compare (sreads @ swrites) in
      let local = Hashtbl.create 4 in
      List.iteri (fun idx n -> Hashtbl.replace local n (List.nth scratch idx)) all;
      let g = function
        | Arm64.Virt n -> (
            match loc_of n with
            | Reg r -> Hashtbl.replace used_cs r (); Arm64.X r
            | Spill -> Arm64.X (Hashtbl.find local n))
        | r -> r
      in
      List.iter (fun n -> push (Arm64.Ldr (Arm64.X (Hashtbl.find local n), Arm64.SP, slot_of n))) sreads;
      push (map_regs g ins);
      List.iter (fun n -> push (Arm64.Str (Arm64.X (Hashtbl.find local n), Arm64.SP, slot_of n))) swrites)
    instrs;
  (List.rev !out, List.sort compare (Hashtbl.fold (fun r () acc -> r :: acc) used_cs []))

(* finalize the frame: prologue (sub sp + save fp/lr + save used callee-saved), and an epilogue
   spliced before every `ret`. The per-value slots sit below the callee-saved save area. *)
let finalize (name : string) (nslots : int) (body : Arm64.instr list) (used_cs : int list) : Arm64.func =
  let open Arm64 in
  let ncs = List.length used_cs in
  let cs_base = 16 + (8 * nslots) in
  let frame = round16 (cs_base + (8 * ncs) + 16) in
  let cs_off i = cs_base + (8 * i) in
  let prologue =
    [ Sub (SP, SP, Imm frame); Stp (X 29, X 30, SP, frame - 16) ]
    @ List.mapi (fun i r -> Str (X r, SP, cs_off i)) used_cs
  in
  let epilogue =
    List.mapi (fun i r -> Ldr (X r, SP, cs_off i)) used_cs
    @ [ Ldp (X 29, X 30, SP, frame - 16); Add (SP, SP, Imm frame) ]
  in
  let body' = List.concat_map (fun i -> if i = Ret then epilogue @ [ Ret ] else [ i ]) body in
  { name; instrs = prologue @ body'; nslots }

(* allocate one function with the chosen strategy *)
let run (strat : strategy) (f : Arm64.func) : Arm64.func =
  let instrs = Array.of_list f.Arm64.instrs in
  let assign =
    match strat with Stack -> stack_alloc instrs | Linscan -> linscan instrs | Graphcolor -> graphcolor instrs
  in
  let body, used_cs = rewrite assign instrs in
  finalize f.Arm64.name f.Arm64.nslots body used_cs

let run_module (strat : strategy) (funcs : Arm64.func list) (cstrings : (string * string) list) : Arm64.modul =
  { Arm64.funcs = List.map (run strat) funcs; cstrings }
