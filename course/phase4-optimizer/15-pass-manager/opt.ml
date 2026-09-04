(* The SIL optimizer — concept 15 (the pass manager). A *pass* is a function-level transform
   `Sil.func -> Sil.func`; the pass MANAGER (`run_pipeline`) runs a pipeline of passes over every
   function of the module. `swiftml4 -O` runs the pipeline before IRGen; `--sil-opt` emits the
   optimized SIL so you can see what each pass did.

   These passes operate on the raw, memory-based SIL (no SSA yet — concept 16 adds mem2reg). They
   are intentionally small; concept 17 turns constant folding + dead-code elimination into the real
   thing. Mirrors swift/lib/SILOptimizer (PassManager + Transforms). *)

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
  | Sil.Cond_br (c, _, _) -> [ c ]
  | Sil.Return (Some v) -> [ v ]
  | _ -> []

(* an instruction we must keep even if its result is unused (it does something observable) *)
let has_side_effect : Sil.instr -> bool = function
  | Sil.Store _ | Sil.Apply _ | Sil.Print _ -> true
  | _ -> false

(* ---- the pass manager: run the pipeline over each function ---- *)
let run_pipeline ?(log = false) (passes : pass list) (m : Sil.modul) : Sil.modul =
  (* TODO(15): the pass manager — every pass over every function, in order, each result feeding
     the next. With [log], trace the pass and function names on stderr. §3. *)
  ignore (log, passes);
  m

(* ---- pass: constant folding (literal arithmetic) ---- *)
let eval_binop (op : Ast.binop) (x : int) (y : int) : int option =
  match op with
  | Ast.Add -> Some (x + y)
  | Ast.Sub -> Some (x - y)
  | Ast.Mul -> Some (x * y)
  | Ast.Div -> if y = 0 then None else Some (x / y) (* never fold ÷0 / %0 — see the note below *)
  | Ast.Mod -> if y = 0 then None else Some (x mod y)
  | _ -> None (* comparisons fold to Bool — left to concept 17 *)
(* ÷0 and %0 have no value to fold to: Swift traps there ("Fatal error: Division by zero",
   exit 133). Our IRGen emits a bare `sdiv`/`srem`, so at runtime the result is undefined rather
   than a trap (PROOFREAD.md §6, open) — the pass must still not invent an answer. *)

let constant_fold (f : Sil.func) : Sil.func =
  (* TODO(15): a SIL pass — fold literal arithmetic. Walk the function in EXECUTION order,
     remembering which values are known Int constants, and replace a binop of two of them with the
     constant it computes, recording that too so chains like (1+2)+3 collapse. [eval_binop] is
     given, and it refuses ÷0 and %0 — there is no value to replace those with. §3. *)
  ignore eval_binop;
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

(* ---- the default `-O` pipeline ---- *)
let default_pipeline = [ { name = "constant-fold"; run = constant_fold }; { name = "dead-instr-elim"; run = dead_instr_elim } ]
let optimize ?(log = false) (m : Sil.modul) : Sil.modul = run_pipeline ~log default_pipeline m
