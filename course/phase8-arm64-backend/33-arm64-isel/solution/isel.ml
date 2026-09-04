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

  (* ===== the learner's holes: TODO(33a) sel_instr, TODO(33b) sel_term ===== *)

  (* lower one non-terminator instruction `%v = instr` (its result lives in slot v) *)
  let sel_instr (v : Sil.value) (i : Sil.instr) : unit =
    match i with
    | Sil.Int_lit n -> materialize (x 9) n; store (x 9) v
    | Sil.Bool_lit b -> materialize (x 9) (if b then 1 else 0); store (x 9) v
    | Sil.Func_ref _ -> () (* recorded in `funcrefs`; the `apply` turns into a direct `bl` *)
    (* a stack slot IS the value's home in this subset (only load/store target it) *)
    | Sil.Alloc_stack name -> emit (Arm64.Comment (Printf.sprintf "alloc_stack %s" name))
    | Sil.Load a -> load (x 9) a; store (x 9) v
    | Sil.Store (src, a) -> load (x 9) src; store (x 9) a
    | Sil.Unop (Ast.Neg, a) -> load (x 9) a; emit (Arm64.Neg (x 9, x 9)); store (x 9) v
    | Sil.Binop (op, l, r) ->
        load (x 9) l;
        load (x 10) r;
        (match op with
        | Ast.Add -> emit (Arm64.Add (x 9, x 9, Arm64.R (x 10)))
        | Ast.Sub -> emit (Arm64.Sub (x 9, x 9, Arm64.R (x 10)))
        | Ast.Mul -> emit (Arm64.Mul (x 9, x 9, x 10))
        | Ast.Div -> emit (Arm64.Sdiv (x 9, x 9, x 10))
        | Ast.Mod -> emit (Arm64.Sdiv (x 11, x 9, x 10)); emit (Arm64.Msub (x 9, x 11, x 10, x 9))
        | Ast.And -> emit (Arm64.And (x 9, x 9, Arm64.R (x 10)))
        | Ast.Or -> emit (Arm64.Orr (x 9, x 9, Arm64.R (x 10)))
        | Ast.Eq | Ast.Ne | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge ->
            emit (Arm64.Cmp (x 9, Arm64.R (x 10))); emit (Arm64.Cset (x 9, cond_of op)));
        store (x 9) v
    (* a direct call: args in x0..x7, result in x0 *)
    | Sil.Apply (callee, args) ->
        List.iteri (fun k a -> load (x k) a) args;
        let name = try Hashtbl.find funcrefs callee with Not_found -> "?" in
        emit (Arm64.Bl ("_" ^ name));
        store (x 0) v
    (* print(_:) — call _printf; the variadic arg goes on the stack at [sp, #0] (Apple ABI) *)
    | Sil.Print a -> (
        match vty a with
        | Types.TBool ->
            load (x 9) a;
            lea_cstring (x 11) (use_cstring "Ltrue" "true");
            lea_cstring (x 12) (use_cstring "Lfalse" "false");
            emit (Arm64.Cmp (x 9, Arm64.Imm 0));
            emit (Arm64.Csel (x 9, x 11, x 12, Arm64.NE)); (* nonzero -> "true" *)
            emit (Arm64.Str (x 9, Arm64.SP, 0));
            lea_cstring (x 0) (use_cstring "Lfmt_str" "%s\n");
            emit (Arm64.Bl "_printf")
        | Types.TString ->
            load (x 9) a;
            emit (Arm64.Str (x 9, Arm64.SP, 0));
            lea_cstring (x 0) (use_cstring "Lfmt_str" "%s\n");
            emit (Arm64.Bl "_printf")
        | _ ->
            load (x 9) a;
            emit (Arm64.Str (x 9, Arm64.SP, 0));
            lea_cstring (x 0) (use_cstring "Lfmt_int" "%lld\n");
            emit (Arm64.Bl "_printf"))
    | other ->
        (* out of v0 scope (struct/enum/class/array/closure ops): a clear failure, not a miscompile *)
        emit (Arm64.Comment (Printf.sprintf "UNSUPPORTED instr for %%%d: %s" v (Sil.string_of_instr f (v, other))))
  in

  (* lower a block terminator *)
  let sel_term (t : Sil.term) : unit =
    match t with
    | Sil.Return (Some a) -> load (x 0) a; epilogue ()
    | Sil.Return None -> if is_main then materialize (x 0) 0; epilogue ()
    | Sil.Br (n, _) -> emit (Arm64.B (blabel n))
    | Sil.Cond_br (c, (tb, _), (eb, _)) ->
        load (x 9) c;
        emit (Arm64.Cmp (x 9, Arm64.Imm 0));
        emit (Arm64.Bcond (Arm64.NE, blabel tb));
        emit (Arm64.B (blabel eb))
    | Sil.Trap _ -> emit (Arm64.Brk 1)
    | Sil.Abort _ -> emit (Arm64.Brk 1)
    | Sil.Unreachable -> ()
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
