(* isel.ml — instruction selection over VIRTUAL registers (concept 34).

   Concept 33's stack machine is gone: each SIL value now becomes a *virtual register* (`Virt v`),
   and register allocation (`regalloc.ml`) maps virtual registers to physical ones (x19..x27,
   callee-saved so they survive calls) or spills them to a frame slot. isel no longer emits a
   prologue/epilogue or a `sub sp` — the frame is finalized AFTER allocation (it depends on which
   callee-saved registers got used and how many spills happened).

   Frame slots (sp-relative; the prologue/epilogue are added by `Regalloc.finalize`):
     [sp, #0  .. #15]   outgoing variadic-call scratch (printf's variadic arg)
     [sp, #16 + 8*v]    a per-value slot — the SPILL home of virtual register v (and the storage
                        of an alloc_stack value, which is only ever a load/store target)

   We still lower the raw (-Onone, memory-based) SIL: variables live in alloc_stack slots, and the
   virtual registers are the literals / loads / arithmetic temporaries between them. *)

let lower_func (_m : Sil.modul) (f : Sil.func) : Arm64.func * (string * string) list =
  let maxv = ref 0 in
  let note v = if v > !maxv then maxv := v in
  List.iter (fun (v, _) -> note v) f.Sil.params;
  List.iter
    (fun (b : Sil.block) ->
      List.iter (fun (v, _) -> note v) b.Sil.args;
      List.iter (fun (v, _) -> note v) b.Sil.instrs)
    f.Sil.blocks;
  let next_tmp = ref (!maxv + 1) in
  let fresh () = let t = !next_tmp in incr next_tmp; Arm64.Virt t in
  (* AAPCS64: the first 8 integer arguments go in x0..x7; arguments 9+ are passed ON THE STACK
     (concept 35). Each function reserves an OUTGOING stack-arg area at the bottom of its frame,
     sized to the widest call it makes (≥2 words, which also holds printf's variadic arg); the value
     slots sit just above it. Incoming stack arguments are read relative to x29 (= the incoming sp,
     set in the prologue): the (8+j)-th parameter is at [x29, #8*j]. *)
  let max_stack_args =
    List.fold_left
      (fun acc (b : Sil.block) ->
        List.fold_left
          (fun acc (_, i) -> match i with Sil.Apply (_, args) -> max acc (List.length args - 8) | _ -> acc)
          acc b.Sil.instrs)
      0 f.Sil.blocks
  in
  let outgoing = max 2 max_stack_args in
  let slot v = (8 * outgoing) + (8 * v) in
  let stackarg_off j = 8 * j in
  let vty v = try Hashtbl.find f.Sil.val_ty v with Not_found -> Types.TInt in
  let blabel bid = Printf.sprintf "L%s_%d" f.Sil.fname bid in
  let is_main = f.Sil.fname = "main" in
  let funcrefs : (Sil.value, string) Hashtbl.t = Hashtbl.create 8 in
  List.iter
    (fun (b : Sil.block) ->
      List.iter (fun (vv, i) -> match i with Sil.Func_ref nm -> Hashtbl.replace funcrefs vv nm | _ -> ()) b.Sil.instrs)
    f.Sil.blocks;
  let cstrings = Hashtbl.create 4 in
  let use_cstring label bytes = Hashtbl.replace cstrings label bytes; label in

  let out = ref [] in
  let emit i = out := i :: !out in
  let v r = Arm64.Virt r in
  let x n = Arm64.X n in

  (* materialize a non-negative 64-bit constant into [dst] (a reg) *)
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
  let lea_cstring dst label = emit (Arm64.Adrp (dst, label)); emit (Arm64.AddSym (dst, dst, label)) in
  let cond_of : Ast.binop -> Arm64.cond = function
    | Ast.Eq -> Arm64.EQ | Ast.Ne -> Arm64.NE | Ast.Lt -> Arm64.LT
    | Ast.Le -> Arm64.LE | Ast.Gt -> Arm64.GT | Ast.Ge -> Arm64.GE
    | _ -> Arm64.EQ
  in

  (* lower one non-terminator instruction `%vr = instr` — emitting VIRTUAL registers *)
  let sel_instr (vr : Sil.value) (i : Sil.instr) : unit =
    match i with
    | Sil.Int_lit n -> materialize (v vr) n
    | Sil.Bool_lit b -> materialize (v vr) (if b then 1 else 0)
    | Sil.Func_ref _ -> ()
    | Sil.Alloc_stack _ -> () (* slot(vr) is its storage; only load/store reference it *)
    | Sil.Load a -> emit (Arm64.Ldr (v vr, Arm64.SP, slot a))
    | Sil.Store (src, a) -> emit (Arm64.Str (v src, Arm64.SP, slot a))
    | Sil.Unop (Ast.Neg, a) -> emit (Arm64.Neg (v vr, v a))
    | Sil.Binop (op, l, r) -> (
        match op with
        | Ast.Add -> emit (Arm64.Add (v vr, v l, Arm64.R (v r)))
        | Ast.Sub -> emit (Arm64.Sub (v vr, v l, Arm64.R (v r)))
        | Ast.Mul -> emit (Arm64.Mul (v vr, v l, v r))
        | Ast.Div -> emit (Arm64.Sdiv (v vr, v l, v r))
        | Ast.Mod -> let q = fresh () in emit (Arm64.Sdiv (q, v l, v r)); emit (Arm64.Msub (v vr, q, v r, v l))
        | Ast.And -> emit (Arm64.And (v vr, v l, Arm64.R (v r)))
        | Ast.Or -> emit (Arm64.Orr (v vr, v l, Arm64.R (v r)))
        | Ast.Eq | Ast.Ne | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge ->
            emit (Arm64.Cmp (v l, Arm64.R (v r))); emit (Arm64.Cset (v vr, cond_of op)))
    | Sil.Apply (callee, args) ->
        (* args 0..7 in x0..x7; args 8+ stored into the outgoing area at [sp, #8*(k-8)] (AAPCS64) *)
        List.iteri
          (fun k a ->
            if k < 8 then emit (Arm64.Mov (x k, Arm64.R (v a)))
            else emit (Arm64.Str (v a, Arm64.SP, stackarg_off (k - 8))))
          args;
        emit (Arm64.Bl ("_" ^ (try Hashtbl.find funcrefs callee with Not_found -> "?")));
        emit (Arm64.Mov (v vr, Arm64.R (x 0)))
    | Sil.Print a -> (
        match vty a with
        | Types.TBool ->
            let tr = fresh () and fl = fresh () and sel = fresh () in
            lea_cstring tr (use_cstring "Ltrue" "true");
            lea_cstring fl (use_cstring "Lfalse" "false");
            emit (Arm64.Cmp (v a, Arm64.Imm 0));
            emit (Arm64.Csel (sel, tr, fl, Arm64.NE));
            emit (Arm64.Str (sel, Arm64.SP, 0));
            lea_cstring (x 0) (use_cstring "Lfmt_str" "%s\n");
            emit (Arm64.Bl "_printf")
        | Types.TString ->
            emit (Arm64.Str (v a, Arm64.SP, 0));
            lea_cstring (x 0) (use_cstring "Lfmt_str" "%s\n");
            emit (Arm64.Bl "_printf")
        | _ ->
            emit (Arm64.Str (v a, Arm64.SP, 0));
            lea_cstring (x 0) (use_cstring "Lfmt_int" "%lld\n");
            emit (Arm64.Bl "_printf"))
    | other -> emit (Arm64.Comment (Printf.sprintf "UNSUPPORTED %%%d: %s" vr (Sil.string_of_instr f (vr, other))))
  in

  let sel_term (t : Sil.term) : unit =
    match t with
    | Sil.Return (Some a) -> emit (Arm64.Mov (x 0, Arm64.R (v a))); emit Arm64.Ret
    | Sil.Return None -> if is_main then materialize (x 0) 0; emit Arm64.Ret
    | Sil.Br (n, _) -> emit (Arm64.B (blabel n))
    | Sil.Cond_br (c, (tb, _), (eb, _)) ->
        emit (Arm64.Cmp (v c, Arm64.Imm 0));
        emit (Arm64.Bcond (Arm64.NE, blabel tb));
        emit (Arm64.B (blabel eb))
    | Sil.Trap _ | Sil.Abort _ -> emit (Arm64.Brk 1)
    | Sil.Unreachable -> ()
  in

  (* incoming params 0..7 arrive in x0..x7; params 8+ arrive on the stack, read via x29 (= the
     incoming sp, set by the prologue): the (8+j)-th parameter is at [x29, #8*j] (AAPCS64) *)
  List.iteri
    (fun k (pv, _) ->
      if k < 8 then emit (Arm64.Mov (v pv, Arm64.R (x k)))
      else emit (Arm64.Ldr (v pv, x 29, 16 + stackarg_off (k - 8))))
    f.Sil.params;
  (* debug info (concept 37): emit a `.loc` source-line directive whenever the line changes, so the
     assembler can build a DWARF line table. Each SIL value's line is in `f.Sil.lines`. *)
  let last_line = ref 0 in
  let emit_loc (vv : Sil.value) : unit =
    match Hashtbl.find_opt f.Sil.lines vv with
    | Some line when line > 0 && line <> !last_line -> last_line := line; emit (Arm64.Loc line)
    | _ -> ()
  in
  let blocks = List.sort (fun (a : Sil.block) b -> compare a.Sil.bid b.Sil.bid) f.Sil.blocks in
  List.iter
    (fun (b : Sil.block) ->
      emit (Arm64.Label (blabel b.Sil.bid));
      List.iter (fun (vv, i) -> emit_loc vv; sel_instr vv i) (List.rev b.Sil.instrs);
      sel_term b.Sil.term)
    blocks;
  (* total local words = the outgoing stack-arg area + one slot per value *)
  let nslots = outgoing + !next_tmp in
  let collected = Hashtbl.fold (fun l b acc -> (l, b) :: acc) cstrings [] in
  ({ Arm64.name = f.Sil.fname; instrs = List.rev !out; nslots }, collected)

(* lower the whole module to per-function vreg ARM64 + the shared C-string set *)
let select (m : Sil.modul) : Arm64.func list * (string * string) list =
  let pairs = List.map (lower_func m) m.Sil.funcs in
  let tbl = Hashtbl.create 8 in
  List.iter (fun (_, css) -> List.iter (fun (l, b) -> Hashtbl.replace tbl l b) css) pairs;
  let cstrings = Hashtbl.fold (fun l b acc -> (l, b) :: acc) tbl [] in
  (List.map fst pairs, cstrings)
