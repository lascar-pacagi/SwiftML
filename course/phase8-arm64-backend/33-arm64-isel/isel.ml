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
     [sp, #LOCALS ..]       saved x29/x30 — the frame record, pushed FIRST
   LOCALS = round16(16 + 8*nvals); the whole frame is LOCALS + 16 bytes.
   The prologue pushes the frame record before carving the locals (`sub sp, #16; stp x29, x30,
   [sp]; mov x29, sp; sub sp, #LOCALS`), so the stp/ldp offset is always 0. A single
   `sub sp, #FRAME; stp …, [sp, #FRAME-16]` overflows stp's +-504 byte range once a function
   has ~60 values (about twenty statements) — `as` refuses the file. `sub`/`add` take a 12-bit
   immediate, so a LOCALS above 4095 is adjusted in several steps.

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
  let locals = round16 (16 + (8 * nvals)) in
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
  (* move sp by n bytes (a multiple of 16): sub/add take a 12-bit immediate, so a huge locals area
     is adjusted in several steps *)
  let rec adjust_sp ~grow n =
    let step = min n 4080 in
    emit
      (if grow then Arm64.Sub (Arm64.SP, Arm64.SP, Arm64.Imm step)
       else Arm64.Add (Arm64.SP, Arm64.SP, Arm64.Imm step));
    if n > step then adjust_sp ~grow (n - step)
  in

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
    adjust_sp ~grow:false locals;
    emit (Arm64.Ldp (x 29, x 30, Arm64.SP, 0));
    emit (Arm64.Add (Arm64.SP, Arm64.SP, Arm64.Imm 16));
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

  (* TODO(33a): lower one non-terminator `%v = instr`, stack-machine style: operands into
       scratch, compute, result back to the slot. §2 gives the ARM64 for each op — including the
       two that are not one instruction (mod is sdiv+msub, a comparison is cmp+cset) and print,
       which goes through printf with Apple's variadic-on-the-stack rule. An op outside v0's scope
       emits a Comment: a visible gap, never a miscompile. *)
  let sel_instr (v : Sil.value) (i : Sil.instr) : unit =
    ignore (v, i, materialize, load, store, lea_cstring, use_cstring, cond_of, funcrefs, vty, x);
    failwith "TODO(33a-isel): select ARM64 for one SIL instruction (the stack-machine templates)"
  in

  (* TODO(33b): the terminators — return (x0, then the epilogue; @main must return 0), the two
       branches, and brk for a trap. §2. *)
  let sel_term (t : Sil.term) : unit =
    ignore (t, blabel, epilogue, is_main, load, materialize, x);
    failwith "TODO(33b-isel): select ARM64 for a block terminator (branches + return)"
  in

  (* ===== driver: prologue, params, blocks in bid order ===== *)
  emit (Arm64.Sub (Arm64.SP, Arm64.SP, Arm64.Imm 16));
  emit (Arm64.Stp (x 29, x 30, Arm64.SP, 0));
  emit (Arm64.Mov (x 29, Arm64.R Arm64.SP));
  adjust_sp ~grow:true locals;
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
