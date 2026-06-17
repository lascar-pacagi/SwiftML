(* isel.ml — instruction selection: SIL -> ARM64 (concept 33).

   v0 is a NAIVE STACK MACHINE: every SIL value gets a frame slot, and each instruction loads its
   operands into scratch registers (x9..x12), computes, and stores the result back to its slot.
   Correct but memory-heavy — every value lives in memory. Concept 34's register-allocation ladder
   is what makes this fast (keeping values in registers); this is the baseline it beats.

   We lower the RAW (-Onone, memory-based) SIL: alloc_stack is a variable's storage, load/store
   move scalars in and out, and control flow is plain branches (raw SIL has no block arguments).

   Frame (sp-relative, sp fixed for the whole body so call-arg shuffling is easy):
     [sp, #0  .. #15]        outgoing variadic-call scratch (printf's variadic arg)
     [sp, #16 .. ]          locals: value %v lives at [sp, #16 + 8*v]
     [sp, #FRAME-16 ..]     saved x29/x30
   FRAME = round16(32 + 8*nvals).

   Scope (v0): Int/Bool scalars, arithmetic, comparisons, if/while/for, function calls, print.
   Structs/enums/classes/ARC/arrays/closures grow coverage in later concepts. *)

let round16 n = (n + 15) / 16 * 16

(* --- per-function lowering --- *)

let lower_func (m : Sil.modul) (f : Sil.func) : Arm64.func * (string * string) list =
  ignore m;
  (* how many value slots: one past the largest value id touched by this function *)
  let maxv = ref 0 in
  let note v = if v > !maxv then maxv := v in
  List.iter (fun (v, _) -> note v) f.Sil.params;
  List.iter
    (fun (b : Sil.block) ->
      List.iter (fun (v, _) -> note v) b.Sil.args;
      List.iter (fun (v, _) -> note v) b.Sil.instrs)
    f.Sil.blocks;
  let nvals = !maxv + 1 in
  let frame = round16 (32 + (8 * nvals)) in
  let slot v = 16 + (8 * v) in
  let vty v = try Hashtbl.find f.Sil.val_ty v with Not_found -> Types.TInt in
  let blabel bid = Printf.sprintf "L%s_%d" f.Sil.fname bid in
  let is_main = f.Sil.fname = "main" in

  (* a SIL value that is a function_ref: remember the target so an `apply` becomes a direct `bl` *)
  let funcrefs : (Sil.value, string) Hashtbl.t = Hashtbl.create 8 in
  List.iter
    (fun (b : Sil.block) ->
      List.iter
        (fun (v, i) -> match i with Sil.Func_ref nm -> Hashtbl.replace funcrefs v nm | _ -> ())
        b.Sil.instrs)
    f.Sil.blocks;

  (* the C-strings this function references (printf formats, true/false) — collected as we go *)
  let cstrings = Hashtbl.create 4 in
  let use_cstring label bytes = Hashtbl.replace cstrings label bytes; label in

  let out = ref [] in (* instructions, reverse order *)
  let emit i = out := i :: !out in
  let emits is = List.iter emit is in

  (* materialize a non-negative 64-bit constant into [dst] *)
  let materialize dst n =
    if n >= 0 && n < 65536 then emit (Arm64.Mov (dst, Arm64.Imm n))
    else begin
      let n64 = Int64.of_int n in
      let hw k = Int64.to_int (Int64.logand (Int64.shift_right_logical n64 (16 * k)) 0xFFFFL) in
      emit (Arm64.Movz (dst, hw 0, 0));
      if hw 1 <> 0 then emit (Arm64.Movk (dst, hw 1, 16));
      if hw 2 <> 0 then emit (Arm64.Movk (dst, hw 2, 32));
      if hw 3 <> 0 then emit (Arm64.Movk (dst, hw 3, 48))
    end
  in
  let load r v = emit (Arm64.Ldr (r, Arm64.SP, slot v)) in
  let store r v = emit (Arm64.Str (r, Arm64.SP, slot v)) in
  let x n = Arm64.X n in

  (* address a C-string into [dst]: the adrp/add @PAGE/@PAGEOFF pair *)
  let lea_cstring dst label =
    emit (Arm64.Adrp (dst, label));
    emit (Arm64.AddSym (dst, dst, label))
  in
  let epilogue () =
    emit (Arm64.Ldp (x 29, x 30, Arm64.SP, frame - 16));
    emit (Arm64.Add (Arm64.SP, Arm64.SP, Arm64.Imm frame));
    emit Arm64.Ret
  in

  let cond_of : Ast.binop -> Arm64.cond = function
    | Ast.Eq -> Arm64.EQ | Ast.Ne -> Arm64.NE | Ast.Lt -> Arm64.LT
    | Ast.Le -> Arm64.LE | Ast.Gt -> Arm64.GT | Ast.Ge -> Arm64.GE
    | _ -> Arm64.EQ
  in

  (* ===== the learner's holes: TODO(33a) sel_instr, TODO(33b) sel_term =====
     This is "instruction selection": each SIL op becomes a short ARM64 sequence. v0 is a STACK
     MACHINE — load operands into scratch (x9/x10/x11), compute, store the result back. The given
     helpers do the plumbing: `materialize dst n` builds a constant; `load r v` is
     `ldr r, [sp, slot v]`; `store r v` is `str r, [sp, slot v]`; `x k` is register xk; `emit i`
     appends one instruction; `lea_cstring dst (use_cstring label bytes)` materializes a string's
     address; `epilogue ()` restores fp/lr and returns; `cond_of op` maps a comparison to a cond. *)

  (* TODO(33a): lower one non-terminator `%v = instr` (its result lives in slot v). Cover:
       Int_lit n / Bool_lit b -> materialize into x9, `store (x 9) v`.
       Func_ref _              -> nothing (recorded in `funcrefs`; the apply becomes a direct bl).
       Alloc_stack name        -> nothing -- in this scalar subset the slot IS the storage (only
                                  load/store target it); a Comment is nice.
       Load a                  -> load x9 from a, store to v.
       Store (src, a)          -> load x9 from src, store to a.
       Unop (Neg, a)           -> load x9, `Neg (x9, x9)`, store to v.
       Binop (op, l, r)        -> load l->x9, r->x10, then per op: Add/Sub/Mul/Sdiv; Mod =
                                  Sdiv(x11,x9,x10) then Msub(x9,x11,x10,x9); And/Orr; a comparison
                                  = `Cmp (x9, R x10)` then `Cset (x9, cond_of op)`. Store x9 to v.
       Apply (callee, args)    -> load args into x0,x1,... (`List.iteri (fun k a -> load (x k) a)`),
                                  `Bl ("_" ^ Hashtbl.find funcrefs callee)`, store x0 to v.
       Print a                 -> by `vty a`: Int -> store the value at [sp,#0]
                                  (`Str (x9, SP, 0)`), x0 = address of the "%lld\n" cstring, `Bl
                                  "_printf"`. Bool -> select "true"/"false" (Csel) then "%s\n".
       any other op            -> emit a Comment (out of v0 scope -- a visible failure, no miscompile).
     Reference: solution/isel.ml. *)
  let sel_instr (v : Sil.value) (i : Sil.instr) : unit =
    ignore (v, i, materialize, load, store, lea_cstring, use_cstring, cond_of, funcrefs, vty, x);
    failwith "TODO(33a-isel): select ARM64 for one SIL instruction (the stack-machine templates)"
  in

  (* TODO(33b): lower a block terminator.
       Return (Some a)  -> load a into x0, `epilogue ()`.
       Return None      -> if `is_main`, `materialize (x 0) 0` (exit code 0); `epilogue ()`.
       Br (n, _)        -> `B (blabel n)`.
       Cond_br (c,(t,_),(e,_)) -> load c into x9, `Cmp (x9, Imm 0)`, `Bcond (NE, blabel t)`,
                                  then `B (blabel e)`  (nonzero c -> the true block).
       Trap _ / Abort _ -> `Brk 1`.  Unreachable -> nothing. *)
  let sel_term (t : Sil.term) : unit =
    ignore (t, blabel, epilogue, is_main, load, materialize, x);
    failwith "TODO(33b-isel): select ARM64 for a block terminator (branches + return)"
  in

  (* ===== driver: prologue, params, blocks in bid order ===== *)
  emit (Arm64.Sub (Arm64.SP, Arm64.SP, Arm64.Imm frame));
  emit (Arm64.Stp (x 29, x 30, Arm64.SP, frame - 16));
  (* spill incoming parameters (x0..) to their slots *)
  List.iteri (fun k (v, _) -> store (x k) v) f.Sil.params;
  let blocks = List.sort (fun (a : Sil.block) b -> compare a.Sil.bid b.Sil.bid) f.Sil.blocks in
  List.iter
    (fun (b : Sil.block) ->
      emit (Arm64.Label (blabel b.Sil.bid));
      List.iter (fun (v, i) -> sel_instr v i) (List.rev b.Sil.instrs);
      sel_term b.Sil.term)
    blocks;
  let collected = Hashtbl.fold (fun l bytes acc -> (l, bytes) :: acc) cstrings [] in
  ({ Arm64.name = f.Sil.fname; instrs = List.rev !out }, collected)

(* --- the module --- *)
let select (m : Sil.modul) : Arm64.modul =
  let pairs = List.map (lower_func m) m.Sil.funcs in
  let funcs = List.map fst pairs in
  (* dedup the C-strings by label across functions *)
  let tbl = Hashtbl.create 8 in
  List.iter (fun (_, css) -> List.iter (fun (l, b) -> Hashtbl.replace tbl l b) css) pairs;
  let cstrings = Hashtbl.fold (fun l b acc -> (l, b) :: acc) tbl [] in
  { Arm64.funcs; cstrings }
