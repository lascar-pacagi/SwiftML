(* SILGen — concept 11 (skeleton). Reference: solution/silgen.ml. Original note: lowers the TYPE-CHECKED tree (`Tast`). Sema resolved
   every enum case to a TAG and every field to an index, so nothing here looks anything up —
   and the shadowing question (`E.red` vs `p.x`) is not asked a second time. PLAN.md §0.1.
   Original note (+ enums): lower the (checked) AST to raw, memory-based SIL.

   Each variable becomes an `alloc_stack` slot, read with `load`, written with `store` (no
   SSA — Phase-4 mem2reg does that). Control flow becomes basic blocks: `if`/`while`/`for`
   build the CFG with `cond_br`/`br`; the AST tree becomes a graph. Each function lowers to
   its own SIL function; top-level statements become `main`. *)

type builder = {
  mutable next_val : int;
  mutable next_block : int;
  mutable cur : Sil.block;
  mutable blocks : Sil.block list; (* all blocks, reverse creation order *)
  vars : (string, Sil.value) Hashtbl.t; (* variable name -> its alloc_stack address value *)
  val_ty : (Sil.value, Types.ty) Hashtbl.t;
  funcs : (string, Types.ty list * Types.ty) Hashtbl.t;
  structs : (string, Types.struct_layout) Hashtbl.t; (* concept 10 *)
  enums : (string, Types.enum_layout) Hashtbl.t; (* concept 11 *)
  mutable loops : (int * int) list; (* stack of (continue-target = header, break-target = exit) *)
}

(* --- the builder API (given) --- *)
let emit (b : builder) (instr : Sil.instr) (ty : Types.ty) : Sil.value =
  let v = b.next_val in
  b.next_val <- v + 1;
  b.cur.Sil.instrs <- (v, instr) :: b.cur.Sil.instrs;
  Hashtbl.replace b.val_ty v ty;
  v

let new_block (b : builder) : Sil.block =
  let blk = { Sil.bid = b.next_block; instrs = []; term = Sil.Unreachable } in
  b.next_block <- b.next_block + 1;
  b.blocks <- blk :: b.blocks;
  blk

let switch_to (b : builder) (blk : Sil.block) = b.cur <- blk
let terminate (b : builder) (t : Sil.term) = if b.cur.Sil.term = Sil.Unreachable then b.cur.Sil.term <- t
let vty (b : builder) (v : Sil.value) : Types.ty = Hashtbl.find b.val_ty v

(* an instruction with NO RESULT — `store`, `print`, a retain or release later on. `emit` still
   hands it a number (which is why the printed SIL skips one at a `store`: `%1 = alloc_stack`,
   `store %0 to %1`, then `%3 = load`), but there is nothing to name, so nothing comes back. *)
let emit_void (b : builder) (instr : Sil.instr) : unit = ignore (emit b instr Types.TVoid)

(* the same pair for `vars`: where a variable's slot is, and how a name comes to have one.
   `addr_of` is total in practice — sema has already rejected the names that are not in scope. *)
let addr_of (b : builder) (name : string) : Sil.value = Hashtbl.find b.vars name
let bind_var (b : builder) (name : string) (addr : Sil.value) : unit =
  Hashtbl.replace b.vars name addr

(* the loop stack, innermost first. `break` and `continue` read it directly — in some concepts
   they need more out of the entry than a block id — but pushing and popping go through here, so
   the two targets are NAMED at the call site. They are not the same block: `continue` on a `for`
   must reach the latch that steps the counter, not the header that tests it. *)
let enter_loop (b : builder) ~(continue_to : int) ~(break_to : int) : unit =
  b.loops <- (continue_to, break_to) :: b.loops

let leave_loop (b : builder) : unit = b.loops <- List.tl b.loops

(* where `break` and `continue` go — the innermost loop's, since `loops` is innermost-first.
   `None` means "not inside a loop", which sema has already rejected; the arm is the compiler's
   own safety net, not a case the source can reach. *)
let break_target (b : builder) : int option =
  match b.loops with (_, ex) :: _ -> Some ex | [] -> None

let continue_target (b : builder) : int option =
  match b.loops with (cont, _) :: _ -> Some cont | [] -> None

let result_ty (op : Ast.binop) (operand : Types.ty) : Types.ty =
  match op with
  | Ast.Eq | Ast.Ne | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge | Ast.And | Ast.Or -> Types.TBool
  | Ast.Add | Ast.Sub | Ast.Mul | Ast.Div | Ast.Mod -> operand

(* --- lowering expressions: returns the SIL value holding the result --- *)

(* A block is a SCOPE for names. Without this, an inner `var x` would overwrite the outer `x`
   in `vars` and never give it back, so every later read of `x` would load the inner slot —
   `var x = 1; if c { var x = 2 }; print(x)` printing 2. Sema already checked the program under
   proper scoping; SILGen only has to stop its own table from leaking. *)
let restore_vars (b : builder) (saved : (string, Sil.value) Hashtbl.t) : unit =
  Hashtbl.reset b.vars;
  Hashtbl.iter (fun k v -> Hashtbl.replace b.vars k v) saved

let rec gen_expr (b : builder) (e : Tast.expr) : Sil.value =
  (* `ty` is what Sema concluded — the whole of what used to be `gen_expr_as` *)
  let ty = e.Tast.ty in
  match e.Tast.e with
  (* THE COERCION, already decided: a literal that checked at Double is BORN a Double *)
  | Tast.Int_lit n when ty = Types.TDouble -> emit b (Sil.Float_lit (float_of_int n)) Types.TDouble
  | Tast.Int_lit n -> emit b (Sil.Int_lit n) Types.TInt
  | Tast.Double_lit f -> emit b (Sil.Float_lit f) Types.TDouble
  | Tast.Bool_lit x -> emit b (Sil.Bool_lit x) Types.TBool
  | Tast.String_lit str -> emit b (Sil.String_lit str) Types.TString
  | Tast.Coerce e0 -> gen_expr b e0
  | Tast.Local x ->
      let addr = addr_of b x in
      emit b (Sil.Load addr) (vty b addr) (* the slot's element type *)
  | Tast.Unary (op, e0) ->
      let v = gen_expr b e0 in
      emit b (Sil.Unop (op, v)) ty
  (* SHORT-CIRCUIT `&&` / `||` (concept 06 semantics, lowered here) — NOT bitwise: the right operand
     is evaluated only on the deciding edge, so its side effects (a trapping `a[i]` in `i < n && a[i]`,
     a force-unwrap, a throwing call) never run on the short path. Lowered to a cond_br diamond, the
     result merged through a stack slot (mem2reg promotes it to a phi). *)
  | Tast.Binary (((Ast.And | Ast.Or) as op), l, r) ->
      let lv = gen_expr b l in
      (* the slot the two answers meet in — named for the operator it serves, since this arm
         lowers both. mem2reg turns it into a phi in Phase 4. *)
      let slot = emit b (Sil.Alloc_stack (if op = Ast.And then "$and" else "$or")) Types.TBool in
      emit_void b (Sil.Store (lv, slot));
      let rhs_b = new_block b and merge = new_block b in
      let t_tgt, f_tgt =
        if op = Ast.And then (rhs_b.Sil.bid, merge.Sil.bid) else (merge.Sil.bid, rhs_b.Sil.bid)
      in
      terminate b (Sil.Cond_br (lv, t_tgt, f_tgt));
      switch_to b rhs_b;
      let rv = gen_expr b r in
      emit_void b (Sil.Store (rv, slot));
      terminate b (Sil.Br merge.Sil.bid);
      switch_to b merge;
      emit b (Sil.Load slot) Types.TBool
  | Tast.Binary (op, l, r) -> (
      match l.Tast.ty with
      | Types.TEnum _ when op = Ast.Eq || op = Ast.Ne ->
          (* enum equality is tag comparison (payload-free enums only — see sema) *)
          let lv = gen_expr b l and rv = gen_expr b r in
          let lt = emit b (Sil.Enum_tag lv) Types.TInt in
          let rt = emit b (Sil.Enum_tag rv) Types.TInt in
          emit b (Sil.Binop (op, lt, rt)) Types.TBool
      | _ ->
          (* Both operands already carry their final type, and so does this node. The version
             that worked this out for itself re-generated the left operand and left the dead
             copy in the block — PLAN.md §0.1. *)
          let lv = gen_expr b l in
          let rv = gen_expr b r in
          emit b (Sil.Binop (op, lv, rv)) ty)
  (* RESOLVED calls — Sema decided initializer vs. function vs. print *)
  | Tast.Struct_init (_, args) -> emit b (Sil.Struct (List.map (gen_expr b) args)) ty
  | Tast.Fn_call (f, args) ->
      let argvs = List.map (gen_expr b) args in
      let fr = emit b (Sil.Func_ref f) ty in
      emit b (Sil.Apply (fr, argvs)) ty
  | Tast.Print a -> emit b (Sil.Print (gen_expr b a)) Types.TVoid
  (* An enum case — construction, with the TAG supplied by Sema. The guard this replaces asked
     `(not (Hashtbl.mem b.vars tn)) && Hashtbl.mem b.enums tn`: SILGen restating Sema's shadowing
     rule in its own vocabulary, and having to agree with it by hand. *)
  | Tast.Enum_case (_, tag, payload) ->
      ignore (tag, payload);
      (* TODO(11g/11h): construct the enum value. Sema hands you the TAG and, for a case with
         associated values, the checked payload — so the shadowing question is already settled
         and there is no registry to consult. §2's SIL table names the instruction; lowering it
         by hand is the point of this concept. *)
      failwith "TODO(11g): construct an enum case"
  | Tast.Raw_value e0 ->
      ignore e0;
      (* TODO(11i): `.rawValue` — sema already established the enum was declared `: Int`, so
         there is nothing to CHECK here, only the read. §2's SIL table names the instruction
         that yields the case index, and says what type that index has. §3. *)
      failwith "TODO(11i): lower `.rawValue` to the tag read"
  | Tast.Field (e0, i, _) -> emit b (Sil.Struct_extract (gen_expr b e0, i)) ty

(* --- lowering statements; gen_block stops after a terminator (dead code) --- *)
let rec gen_block (b : builder) (stmts : Tast.stmt list) : unit =
  let saved = Hashtbl.copy b.vars in
  let rec go stmts =
    match stmts with
    | [] -> ()
    | s :: rest ->
        gen_stmt b s;
        if b.cur.Sil.term = Sil.Unreachable then go rest
  in
  go stmts;
  restore_vars b saved

and gen_stmt (b : builder) (s : Tast.stmt) : unit =
  match s with
  | Tast.Let { name; value; _ } ->
      let v = gen_expr b value in
      let addr = emit b (Sil.Alloc_stack name) (vty b v) in
      bind_var b name addr;
      emit_void b (Sil.Store (v, addr))
  | Tast.Assign { name; value; _ } ->
      let v = gen_expr b value in
      emit_void b (Sil.Store (v, addr_of b name))
  | Tast.Set_member { obj; field = i; value; _ } ->
      (* `p.x = e`: take the field's ADDRESS in p's slot, then store — this is what makes a
         struct a value type. The index is Sema's. *)
      let v = gen_expr b value in
      let slot = Hashtbl.find b.vars obj in
      let faddr = emit b (Sil.Struct_element_addr (slot, i)) (vty b v) in
      emit_void b (Sil.Store (v, faddr))
  | Tast.Expr_stmt e -> ignore (gen_expr b e)
  | Tast.Return (eo, _) -> (
      match eo with
      | Some e ->
          let v = gen_expr b e in
          terminate b (Sil.Return (Some v))
      | None -> terminate b (Sil.Return None))
  | Tast.If { cond; then_blk; else_blk; _ } ->
      let c = gen_expr b cond in
      let then_b = new_block b in
      let merge = new_block b in
      let else_b = match else_blk with Some _ -> new_block b | None -> merge in
      terminate b (Sil.Cond_br (c, then_b.Sil.bid, else_b.Sil.bid));
      switch_to b then_b;
      gen_block b then_blk;
      terminate b (Sil.Br merge.Sil.bid);
      (match else_blk with
      | Some e ->
          switch_to b else_b;
          gen_block b e;
          terminate b (Sil.Br merge.Sil.bid)
      | None -> ());
      switch_to b merge
  | Tast.While { cond; body; _ } ->
      let header = new_block b and body_b = new_block b and exit_b = new_block b in
      terminate b (Sil.Br header.Sil.bid);
      switch_to b header;
      let c = gen_expr b cond in
      terminate b (Sil.Cond_br (c, body_b.Sil.bid, exit_b.Sil.bid));
      switch_to b body_b;
      enter_loop b ~continue_to:header.Sil.bid ~break_to:exit_b.Sil.bid;
      gen_block b body;
      terminate b (Sil.Br header.Sil.bid);
      leave_loop b;
      switch_to b exit_b
  | Tast.For { var; lo; hi; body; _ } ->
      (* desugar `for v in lo ..< hi { body }` into a counted while loop *)
      let lov = gen_expr b lo in
      let hiv = gen_expr b hi in
      let addr = emit b (Sil.Alloc_stack var) Types.TInt in
      bind_var b var addr;
      emit_void b (Sil.Store (lov, addr));
      (* header -> body -> latch (the increment) -> header; continue jumps to the latch so
         it doesn't skip `v = v + 1` (that would loop forever) *)
      let header = new_block b and body_b = new_block b in
      let latch = new_block b and exit_b = new_block b in
      terminate b (Sil.Br header.Sil.bid);
      switch_to b header;
      let cur_v = emit b (Sil.Load addr) Types.TInt in
      let c = emit b (Sil.Binop (Ast.Lt, cur_v, hiv)) Types.TBool in
      terminate b (Sil.Cond_br (c, body_b.Sil.bid, exit_b.Sil.bid));
      switch_to b body_b;
      enter_loop b ~continue_to:latch.Sil.bid ~break_to:exit_b.Sil.bid;
      gen_block b body;
      terminate b (Sil.Br latch.Sil.bid);
      leave_loop b;
      switch_to b latch;
      let cv = emit b (Sil.Load addr) Types.TInt in
      let one = emit b (Sil.Int_lit 1) Types.TInt in
      let inc = emit b (Sil.Binop (Ast.Add, cv, one)) Types.TInt in
      emit_void b (Sil.Store (inc, addr));
      terminate b (Sil.Br header.Sil.bid);
      switch_to b exit_b
  | Tast.Break _ -> ( match break_target b with Some ex -> terminate b (Sil.Br ex) | None -> ())
  | Tast.Continue _ -> ( match continue_target b with Some c -> terminate b (Sil.Br c) | None -> ())

(* --- lowering a function: params get slots; then the body --- *)
let lower_func structs enums funcs (name : string) (params : (string * Types.ty) list) (ret : Types.ty)
    (body : Tast.stmt list) : Sil.func =
  let val_ty = Hashtbl.create 16 in
  let entry = { Sil.bid = 0; instrs = []; term = Sil.Unreachable } in
  let b =
    { next_val = 0; next_block = 1; cur = entry; blocks = [ entry ]; vars = Hashtbl.create 16; val_ty; funcs; structs; enums; loops = [] }
  in
  (* parameters are the function's first SIL values %0..%(n-1) *)
  let sil_params =
    List.map
      (fun (_, pty) ->
        let pv = b.next_val in
        b.next_val <- pv + 1;
        Hashtbl.replace val_ty pv pty;
        (pv, pty))
      params
  in
  (* store each parameter into a stack slot so the body's load/store is uniform *)
  List.iter2
    (fun (pv, pty) (pname, _) ->
      let addr = emit b (Sil.Alloc_stack pname) pty in
      bind_var b pname addr;
      emit_void b (Sil.Store (pv, addr)))
    sil_params params;
  gen_block b body;
  terminate b (if ret = Types.TVoid then Sil.Return None else Sil.Unreachable);
  { Sil.fname = name; params = sil_params; ret; blocks = b.blocks; val_ty }

(* --- the entry point: a checked program -> a SIL module --- *)
let lower (prog : Tast.program) : Sil.modul =
  (* Nothing is resolved here: the layouts were built by Sema and travel with the tree. *)
  let structs : (string, Types.struct_layout) Hashtbl.t = Hashtbl.create 16 in
  let enums : (string, Types.enum_layout) Hashtbl.t = Hashtbl.create 16 in
  let struct_layouts =
    List.filter_map
      (function Tast.IStruct l -> Hashtbl.replace structs l.Types.sl_name l; Some l | _ -> None)
      prog.Tast.items
  in
  let enum_layouts =
    List.filter_map
      (function Tast.IEnum l -> Hashtbl.replace enums l.Types.el_name l; Some l | _ -> None)
      prog.Tast.items
  in
  let funcs = Hashtbl.create 16 in
  List.iter
    (function
      | Tast.IFunc f ->
          Hashtbl.replace funcs f.Tast.fname
            (List.map (fun (p : Tast.param) -> p.Tast.pty) f.Tast.params, f.Tast.ret)
      | _ -> ())
    prog.Tast.items;
  let funcdefs =
    List.filter_map
      (function
        | Tast.IFunc f ->
            let params = List.map (fun (p : Tast.param) -> (p.Tast.pname, p.Tast.pty)) f.Tast.params in
            Some (lower_func structs enums funcs f.Tast.fname params f.Tast.ret f.Tast.body)
        | _ -> None)
      prog.Tast.items
  in
  let main_body = List.filter_map (function Tast.IStmt s -> Some s | _ -> None) prog.Tast.items in
  let main = lower_func structs enums funcs "main" [] Types.TVoid main_body in
  { Sil.funcs = funcdefs @ [ main ]; structs = struct_layouts; enums = enum_layouts }
