(* FROZEN SOLUTION — concept 08 SILGen: lower the (checked) AST to raw, memory-based SIL.

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

let result_ty (op : Ast.binop) (operand : Types.ty) : Types.ty =
  match op with
  | Ast.Eq | Ast.Ne | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge | Ast.And | Ast.Or -> Types.TBool
  | Ast.Add | Ast.Sub | Ast.Mul | Ast.Div | Ast.Mod -> operand

(* --- lowering expressions: returns the SIL value holding the result --- *)
let rec gen_expr (b : builder) (e : Ast.expr) : Sil.value =
  match e with
  | Ast.Int_lit (n, _) -> emit b (Sil.Int_lit n) Types.TInt
  | Ast.Double_lit (f, _) -> emit b (Sil.Float_lit f) Types.TDouble
  | Ast.Bool_lit (x, _) -> emit b (Sil.Bool_lit x) Types.TBool
  | Ast.String_lit (s, _) -> emit b (Sil.String_lit s) Types.TString
  (* `e as T`: generate the operand AT the written type (see gen_expr_as). *)
  | Ast.Ascribe (e0, tyname, _) -> (
      match Types.of_name tyname with
      | Some t -> gen_expr_as b e0 t
      | None -> gen_expr b e0)
  | Ast.Var (x, _) ->
      let addr = Hashtbl.find b.vars x in
      emit b (Sil.Load addr) (vty b addr) (* the slot's element type *)
  | Ast.Unary (op, e0, _) ->
      let v = gen_expr b e0 in
      emit b (Sil.Unop (op, v)) (vty b v)
  (* SHORT-CIRCUIT `&&` / `||` (concept 06 semantics, lowered here) — NOT bitwise: the right operand
     is evaluated only on the deciding edge, so its side effects (a trapping `a[i]` in `i < n && a[i]`,
     a force-unwrap, a throwing call) never run on the short path. Lowered to a cond_br diamond, the
     result merged through a stack slot (mem2reg promotes it to a phi). *)
  | Ast.Binary ((Ast.And | Ast.Or) as op, l, r, _) ->
      let lv = gen_expr b l in
      let slot = emit b (Sil.Alloc_stack "land") Types.TBool in
      ignore (emit b (Sil.Store (lv, slot)) Types.TVoid);
      let rhs_b = new_block b and merge = new_block b in
      let t_tgt, f_tgt =
        if op = Ast.And then (rhs_b.Sil.bid, merge.Sil.bid) else (merge.Sil.bid, rhs_b.Sil.bid)
      in
      terminate b (Sil.Cond_br (lv, t_tgt, f_tgt));
      switch_to b rhs_b;
      let rv = gen_expr b r in
      ignore (emit b (Sil.Store (rv, slot)) Types.TVoid);
      terminate b (Sil.Br merge.Sil.bid);
      switch_to b merge;
      emit b (Sil.Load slot) Types.TBool
  | Ast.Binary (op, l, r, _) ->
      let lv = gen_expr b l and rv = gen_expr b r in
      let operand = if vty b lv = Types.TDouble || vty b rv = Types.TDouble then Types.TDouble else vty b lv in
      emit b (Sil.Binop (op, lv, rv)) (result_ty op operand)
  | Ast.Call (f, args, _) ->
      let argvs = List.map (gen_expr b) args in
      if Hashtbl.mem b.funcs f then (
        let _, ret = Hashtbl.find b.funcs f in
        let fr = emit b (Sil.Func_ref f) ret in
        emit b (Sil.Apply (fr, argvs)) ret)
      else emit b (Sil.Print (List.hd argvs)) Types.TVoid

(* Generate [e] AT an expected type. The only coercion this early is the integer literal that
   checks at Double: it must be BORN a Double, or the slot receives an i64 bit-pattern and
   `let d: Double = 1` reads back as 4.94e-324. The recursion mirrors sema's `is_int_literal`. *)
and gen_expr_as (b : builder) (e : Ast.expr) (expected : Types.ty) : Sil.value =
  match (e, expected) with
  | Ast.Int_lit (n, _), Types.TDouble -> emit b (Sil.Float_lit (float_of_int n)) Types.TDouble
  | Ast.Unary (op, e0, _), Types.TDouble ->
      let v = gen_expr_as b e0 Types.TDouble in
      emit b (Sil.Unop (op, v)) Types.TDouble
  | Ast.Binary (((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div) as op), l, r, _), Types.TDouble ->
      let lv = gen_expr_as b l Types.TDouble and rv = gen_expr_as b r Types.TDouble in
      emit b (Sil.Binop (op, lv, rv)) Types.TDouble
  | _ -> gen_expr b e

(* --- lowering statements; gen_block stops after a terminator (dead code) --- *)
let rec gen_block (b : builder) (stmts : Ast.stmt list) : unit =
  match stmts with
  | [] -> ()
  | s :: rest ->
      gen_stmt b s;
      if b.cur.Sil.term = Sil.Unreachable then gen_block b rest

and gen_stmt (b : builder) (s : Ast.stmt) : unit =
  match s with
  | Ast.Let { name; annot; value; _ } ->
      (* an annotation makes the slot that type, and the value is generated AT it *)
      let v =
        match annot with
        | Some n -> ( match Types.of_name n with Some t -> gen_expr_as b value t | None -> gen_expr b value)
        | None -> gen_expr b value
      in
      let addr = emit b (Sil.Alloc_stack name) (vty b v) in
      Hashtbl.replace b.vars name addr;
      ignore (emit b (Sil.Store (v, addr)) Types.TVoid)
  | Ast.Assign { name; value; _ } ->
      let v = gen_expr b value in
      ignore (emit b (Sil.Store (v, Hashtbl.find b.vars name)) Types.TVoid)
  | Ast.Expr_stmt (e, _) -> ignore (gen_expr b e)
  | Ast.Return (eo, _) -> (
      match eo with
      | Some e ->
          let v = gen_expr b e in
          terminate b (Sil.Return (Some v))
      | None -> terminate b (Sil.Return None))
  | Ast.If { cond; then_blk; else_blk; _ } ->
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
  | Ast.While { cond; body; _ } ->
      let header = new_block b and body_b = new_block b and exit_b = new_block b in
      terminate b (Sil.Br header.Sil.bid);
      switch_to b header;
      let c = gen_expr b cond in
      terminate b (Sil.Cond_br (c, body_b.Sil.bid, exit_b.Sil.bid));
      switch_to b body_b;
      b.loops <- (header.Sil.bid, exit_b.Sil.bid) :: b.loops;
      gen_block b body;
      terminate b (Sil.Br header.Sil.bid);
      b.loops <- List.tl b.loops;
      switch_to b exit_b
  | Ast.For { var; lo; hi; body; _ } ->
      (* desugar `for v in lo ..< hi { body }` into a counted while loop *)
      let lov = gen_expr b lo in
      let hiv = gen_expr b hi in
      let addr = emit b (Sil.Alloc_stack var) Types.TInt in
      Hashtbl.replace b.vars var addr;
      ignore (emit b (Sil.Store (lov, addr)) Types.TVoid);
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
      b.loops <- (latch.Sil.bid, exit_b.Sil.bid) :: b.loops;
      gen_block b body;
      terminate b (Sil.Br latch.Sil.bid);
      b.loops <- List.tl b.loops;
      switch_to b latch;
      let cv = emit b (Sil.Load addr) Types.TInt in
      let one = emit b (Sil.Int_lit 1) Types.TInt in
      let inc = emit b (Sil.Binop (Ast.Add, cv, one)) Types.TInt in
      ignore (emit b (Sil.Store (inc, addr)) Types.TVoid);
      terminate b (Sil.Br header.Sil.bid);
      switch_to b exit_b
  | Ast.Break _ -> ( match b.loops with (_, ex) :: _ -> terminate b (Sil.Br ex) | [] -> ())
  | Ast.Continue _ -> ( match b.loops with (cont, _) :: _ -> terminate b (Sil.Br cont) | [] -> ())

(* --- lowering a function: params get slots; then the body --- *)
let lower_func funcs (name : string) (params : (string * Types.ty) list) (ret : Types.ty)
    (body : Ast.stmt list) : Sil.func =
  let val_ty = Hashtbl.create 16 in
  let entry = { Sil.bid = 0; instrs = []; term = Sil.Unreachable } in
  let b =
    { next_val = 0; next_block = 1; cur = entry; blocks = [ entry ]; vars = Hashtbl.create 16; val_ty; funcs; loops = [] }
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
      Hashtbl.replace b.vars pname addr;
      ignore (emit b (Sil.Store (pv, addr)) Types.TVoid))
    sil_params params;
  gen_block b body;
  terminate b (if ret = Types.TVoid then Sil.Return None else Sil.Unreachable);
  { Sil.fname = name; params = sil_params; ret; blocks = b.blocks; val_ty }

(* --- the entry point: a checked program -> a SIL module --- *)
let lower (prog : Ast.program) : Sil.modul =
  let ty_of_name n = Option.value (Types.of_name n) ~default:Types.TInt in
  let ret_of f = match f.Ast.ret with None -> Types.TVoid | Some n -> ty_of_name n in
  let funcs = Hashtbl.create 16 in
  List.iter
    (function
      | Ast.IFunc f ->
          let ptypes = List.map (fun (pr : Ast.param) -> ty_of_name pr.Ast.ptype) f.Ast.params in
          Hashtbl.replace funcs f.Ast.fname (ptypes, ret_of f)
      | Ast.IStmt _ -> ())
    prog.Ast.items;
  let funcdefs =
    List.filter_map
      (function
        | Ast.IFunc f ->
            let params = List.map (fun (pr : Ast.param) -> (pr.Ast.pname, ty_of_name pr.Ast.ptype)) f.Ast.params in
            Some (lower_func funcs f.Ast.fname params (ret_of f) f.Ast.body)
        | Ast.IStmt _ -> None)
      prog.Ast.items
  in
  let main_body = List.filter_map (function Ast.IStmt s -> Some s | Ast.IFunc _ -> None) prog.Ast.items in
  let main = lower_func funcs "main" [] Types.TVoid main_body in
  { Sil.funcs = funcdefs @ [ main ] }
