(* SILGen — concept 13 (skeleton). Carries the switch compiler complete; you add the OPTIONAL
   lowering (the TODO(13) holes) — optionals are an enum { none=0; some=1 }, so it reuses Enum*.

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
  ret : Types.ty; (* the enclosing function's return type — for return-wrapping (concept 13) *)
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

(* resolve a written type name (with optional trailing `?`) to a SIL type — concept 13 *)
let rec resolve_name (b : builder) (name : string) : Types.ty =
  if String.length name > 0 && name.[String.length name - 1] = '?' then
    Types.TOptional (resolve_name b (String.sub name 0 (String.length name - 1)))
  else
    match Types.of_name name with
    | Some t -> t
    | None ->
        if Hashtbl.mem b.structs name then Types.TStruct name
        else if Hashtbl.mem b.enums name then Types.TEnum name
        else Types.TInt

let is_nil = function Ast.Nil _ -> true | _ -> false

(* --- lowering expressions: returns the SIL value holding the result --- *)
let rec gen_expr (b : builder) (e : Ast.expr) : Sil.value =
  match e with
  | Ast.Int_lit (n, _) -> emit b (Sil.Int_lit n) Types.TInt
  | Ast.Double_lit (f, _) -> emit b (Sil.Float_lit f) Types.TDouble
  | Ast.Bool_lit (x, _) -> emit b (Sil.Bool_lit x) Types.TBool
  | Ast.String_lit (s, _) -> emit b (Sil.String_lit s) Types.TString
  (* `e as T`: generate the operand AT the written type, exactly like an annotated `let`.
     A literal tree that checks at Double must be BORN a Double — lowering it as an Int and
     relabelling the type gives `icmp` on a float constant. *)
  | Ast.Ascribe (e0, tyname, _) -> gen_expr_as b e0 (resolve_name b tyname)
  (* `e as T` is a *type-level* coercion: sema only accepts it where the operand
     already checks at T, so there is nothing to emit. *)
  | Ast.Ascribe (e0, _, _) -> gen_expr b e0
  | Ast.Var (x, _) ->
      let addr = Hashtbl.find b.vars x in
      emit b (Sil.Load addr) (vty b addr) (* the slot's element type *)
  | Ast.Unary (op, e0, _) ->
      let v = gen_expr b e0 in
      emit b (Sil.Unop (op, v)) (vty b v)
  (* `opt == nil` / `opt != nil`: compare the tag with 0 (the `none` case) — concept 13 *)
  | Ast.Binary (op, l, r, _) when (op = Ast.Eq || op = Ast.Ne) && (is_nil l || is_nil r) ->
      let ov = gen_expr b (if is_nil l then r else l) in
      let tag = emit b (Sil.Enum_tag ov) Types.TInt in
      let zero = emit b (Sil.Int_lit 0) Types.TInt in
      emit b (Sil.Binop (op, tag, zero)) Types.TBool
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
      (match vty b lv with
      | Types.TEnum _ when op = Ast.Eq || op = Ast.Ne ->
          (* enum equality is tag comparison (payload-free enums only — see sema) *)
          let lt = emit b (Sil.Enum_tag lv) Types.TInt in
          let rt = emit b (Sil.Enum_tag rv) Types.TInt in
          emit b (Sil.Binop (op, lt, rt)) Types.TBool
      | _ ->
          let operand = if vty b lv = Types.TDouble || vty b rv = Types.TDouble then Types.TDouble else vty b lv in
          emit b (Sil.Binop (op, lv, rv)) (result_ty op operand))
  | Ast.Call (f, args, _) ->
      if Hashtbl.mem b.structs f then (
        (* a struct field may be optional, so wrap each argument to its field type *)
        let sl = Hashtbl.find b.structs f in
        let argvs = List.map2 (fun (_, e) (_, ft) -> gen_expr_as b e ft) args sl.Types.sl_fields in
        emit b (Sil.Struct argvs) (Types.TStruct f))
      else if Hashtbl.mem b.funcs f then (
        let ptypes, ret = Hashtbl.find b.funcs f in
        let argvs = List.map2 (fun (_, e) pt -> gen_expr_as b e pt) args ptypes in
        let fr = emit b (Sil.Func_ref f) ret in
        emit b (Sil.Apply (fr, argvs)) ret)
      else
        let argvs = List.map (fun (_, e) -> gen_expr b e) args in
        emit b (Sil.Print (List.hd argvs)) Types.TVoid
  (* `E.case` — a no-payload enum case (concept 11) *)
  | Ast.Member (Ast.Var (tn, _), case, _) when Hashtbl.mem b.enums tn ->
      let el = Hashtbl.find b.enums tn in
      emit b (Sil.Enum (Option.get (Types.case_index el case), [])) (Types.TEnum tn)
  | Ast.Member (e0, fld, _) -> (
      let sv = gen_expr b e0 in
      match vty b sv with
      | Types.TStruct sn ->
          let sl = Hashtbl.find b.structs sn in
          emit b (Sil.Struct_extract (sv, Option.get (Types.field_index sl fld)))
            (Option.get (Types.field_type sl fld))
      | Types.TEnum _ -> emit b (Sil.Enum_tag sv) Types.TInt (* `.rawValue` = the tag *)
      | _ -> assert false)
  (* `E.case(args)` — a payload-carrying enum case (concept 11) *)
  | Ast.Method_call (Ast.Var (tn, _), case, args, _) when Hashtbl.mem b.enums tn ->
      let el = Hashtbl.find b.enums tn in
      let argvs = List.map (fun (_, e) -> gen_expr b e) args in
      emit b (Sil.Enum (Option.get (Types.case_index el case), argvs)) (Types.TEnum tn)
  | Ast.Method_call _ -> assert false (* sema rejected non-enum method calls *)
  (* optionals are an enum { none(tag 0); some(tag 1, payload) } — concept 13 *)
  | Ast.Nil _ -> assert false (* nil only appears in a checked context; gen_expr_as handles it *)
  | Ast.Force_unwrap (e0, _) ->
      (* TODO(13): `e!` — a tag test, and on `none` a `Sil.Trap` whose message and exit code the
         tests compare against swiftc's. §2 quotes it. *)
      ignore e0;
      failwith "TODO(13-silgen): lower force-unwrap (tag check, trap on nil, extract payload)"
  (* ternary `c ? a : b` — a value-producing diamond (the general case of `&&`/`||`): evaluate the
     condition, branch, evaluate ONLY the taken arm, merge both arms' results through a slot. *)
  | Ast.Ternary (cnd, te, ee, _) ->
      let cv = gen_expr b cnd in
      let then_b = new_block b and else_b = new_block b and merge = new_block b in
      terminate b (Sil.Cond_br (cv, then_b.Sil.bid, else_b.Sil.bid));
      switch_to b then_b;
      let tv = gen_expr b te in
      let t = vty b tv in
      let slot = emit b (Sil.Alloc_stack "tern") t in
      ignore (emit b (Sil.Store (tv, slot)) Types.TVoid);
      terminate b (Sil.Br merge.Sil.bid);
      switch_to b else_b;
      let ev = gen_expr_as b ee t in
      ignore (emit b (Sil.Store (ev, slot)) Types.TVoid);
      terminate b (Sil.Br merge.Sil.bid);
      switch_to b merge;
      emit b (Sil.Load slot) t
  | Ast.Coalesce (a, bexpr, _) ->
      (* TODO(13): `a ?? b` — two paths producing one value, so it needs a slot to merge through
         (the same shape a value-producing `if` needs). §2. *)
      ignore (a, bexpr);
      failwith "TODO(13-silgen): lower nil-coalescing (?? )"

(* lower `e` where an optional is expected — concept 13 *)
and gen_expr_as (b : builder) (e : Ast.expr) (expected : Types.ty) : Sil.value =
  (* TODO(13): the IMPLICIT WRAP — where a `T?` is expected, `nil` becomes `.none`, an already
     optional value passes through, and anything else is wrapped as `.some`. This is the one
     place the enum-as-sugar story becomes code; §2 has the table. *)
  ignore expected;
  gen_expr b e

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
      (* if there's an annotation, the slot has that type and the value is wrapped to it (so
         `let x: Int? = 5` stores `.some(5)`); otherwise the slot is the value's own type *)
      let v, slot_ty =
        match annot with
        | Some n -> let ty = resolve_name b n in (gen_expr_as b value ty, ty)
        | None -> let v = gen_expr b value in (v, vty b v)
      in
      let addr = emit b (Sil.Alloc_stack name) slot_ty in
      Hashtbl.replace b.vars name addr;
      ignore (emit b (Sil.Store (v, addr)) Types.TVoid)
  | Ast.Assign { name; value; _ } ->
      (* wrap to the SLOT's type, not the value's: assigning `7` to an `Int?` var must store
         `.some(7)` (the same implicit wrap as Let/Return/args) *)
      let slot = Hashtbl.find b.vars name in
      let v = gen_expr_as b value (vty b slot) in
      ignore (emit b (Sil.Store (v, slot)) Types.TVoid)
  | Ast.Set_member { obj; field; value; _ } ->
      (* `p.x = e`: take the field's ADDRESS in p's slot, then store — this is what makes a
         struct a value type, since p has its own slot distinct from any copy *)
      let v = gen_expr b value in
      let slot = Hashtbl.find b.vars obj in
      let sn = match vty b slot with Types.TStruct sn -> sn | _ -> assert false in
      let sl = Hashtbl.find b.structs sn in
      let faddr =
        emit b (Sil.Struct_element_addr (slot, Option.get (Types.field_index sl field)))
          (Option.get (Types.field_type sl field))
      in
      ignore (emit b (Sil.Store (v, faddr)) Types.TVoid)
  | Ast.Expr_stmt (e, _) -> ignore (gen_expr b e)
  | Ast.Return (eo, _) -> (
      match eo with
      | Some e ->
          (* wrap to the function's return type (so `return 5` in a `-> Int?` func returns some(5)) *)
          let v = gen_expr_as b e b.ret in
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
  | Ast.If_let { name; opt; then_blk; else_blk; _ } ->
      (* TODO(13): `if let x = opt` — an `if` whose condition is the tag test, and whose then-block
         opens by binding x to the payload. Compare the `if` and `switch` lowerings. §2. *)
      ignore (name, opt, then_blk, else_blk);
      failwith "TODO(13-silgen): lower `if let` (some-check + bind payload)"
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
  | Ast.Switch { subject; cases; default; _ } ->
      (* evaluate the subject once; the discriminant is the enum tag (enum) or the value (Int).
         Then a chain of `tag == k ? caseBlock : nextTest`, each case binding its payload. *)
      let subj = gen_expr b subject in
      let enum_name = match vty b subj with Types.TEnum en -> Some en | _ -> None in
      let disc =
        match enum_name with Some _ -> emit b (Sil.Enum_tag subj) Types.TInt | None -> subj
      in
      let merge = new_block b in
      let key_of = function
        | Ast.PEnumCase (cn, _) ->
            let en = Option.get enum_name in
            Option.get (Types.case_index (Hashtbl.find b.enums en) cn)
        | Ast.PInt n -> n
      in
      let bind_payload pat =
        match (pat, enum_name) with
        | Ast.PEnumCase (cn, bindings), Some en ->
            let tys = Option.get (Types.case_payload (Hashtbl.find b.enums en) cn) in
            List.iteri
              (fun i binding ->
                match binding with
                | Ast.Bind x ->
                    let pv = emit b (Sil.Enum_payload (subj, i)) (List.nth tys i) in
                    let addr = emit b (Sil.Alloc_stack x) (vty b pv) in
                    Hashtbl.replace b.vars x addr;
                    ignore (emit b (Sil.Store (pv, addr)) Types.TVoid)
                | Ast.Ignore -> ())
              bindings
        | _ -> ()
      in
      let rec dispatch = function
        | [] -> (
            match default with
            | Some body -> gen_block b body; terminate b (Sil.Br merge.Sil.bid)
            | None -> terminate b Sil.Unreachable (* an exhaustive enum switch: no case left *))
        | (pat, body) :: rest ->
            let k = emit b (Sil.Int_lit (key_of pat)) Types.TInt in
            let c = emit b (Sil.Binop (Ast.Eq, disc, k)) Types.TBool in
            let case_b = new_block b and next_b = new_block b in
            terminate b (Sil.Cond_br (c, case_b.Sil.bid, next_b.Sil.bid));
            switch_to b case_b;
            bind_payload pat;
            gen_block b body;
            terminate b (Sil.Br merge.Sil.bid);
            switch_to b next_b;
            dispatch rest
      in
      dispatch cases;
      switch_to b merge
  | Ast.Break _ -> ( match b.loops with (_, ex) :: _ -> terminate b (Sil.Br ex) | [] -> ())
  | Ast.Continue _ -> ( match b.loops with (cont, _) :: _ -> terminate b (Sil.Br cont) | [] -> ())

(* --- lowering a function: params get slots; then the body --- *)
let lower_func structs enums funcs (name : string) (params : (string * Types.ty) list) (ret : Types.ty)
    (body : Ast.stmt list) : Sil.func =
  let val_ty = Hashtbl.create 16 in
  let entry = { Sil.bid = 0; instrs = []; term = Sil.Unreachable } in
  let b =
    { next_val = 0; next_block = 1; cur = entry; blocks = [ entry ]; vars = Hashtbl.create 16; val_ty; funcs; structs; enums; ret; loops = [] }
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
  (* struct + enum registries first (names, then layouts) so any type name resolves *)
  let structs : (string, Types.struct_layout) Hashtbl.t = Hashtbl.create 16 in
  let enums : (string, Types.enum_layout) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (function
      | Ast.IStruct s -> Hashtbl.replace structs s.Ast.sname { Types.sl_name = s.Ast.sname; sl_fields = [] }
      | Ast.IEnum e -> Hashtbl.replace enums e.Ast.ename { Types.el_name = e.Ast.ename; el_cases = []; el_raw = e.Ast.eraw <> None }
      | _ -> ())
    prog.Ast.items;
  let rec ty_of_name n =
    if String.length n > 0 && n.[String.length n - 1] = '?' then
      Types.TOptional (ty_of_name (String.sub n 0 (String.length n - 1)))
    else
      match Types.of_name n with
      | Some t -> t
      | None ->
          if Hashtbl.mem structs n then Types.TStruct n
          else if Hashtbl.mem enums n then Types.TEnum n
          else Types.TInt
  in
  List.iter
    (function
      | Ast.IStruct s ->
          let fs = List.map (fun (fl : Ast.field) -> (fl.Ast.fld_name, ty_of_name fl.Ast.fld_ty)) s.Ast.sfields in
          Hashtbl.replace structs s.Ast.sname { Types.sl_name = s.Ast.sname; sl_fields = fs }
      | Ast.IEnum e ->
          let cs = List.map (fun (c : Ast.enum_case) -> (c.Ast.cname, List.map ty_of_name c.Ast.payload)) e.Ast.ecases in
          Hashtbl.replace enums e.Ast.ename { Types.el_name = e.Ast.ename; el_cases = cs; el_raw = e.Ast.eraw <> None }
      | _ -> ())
    prog.Ast.items;
  let ret_of f = match f.Ast.ret with None -> Types.TVoid | Some n -> ty_of_name n in
  let funcs = Hashtbl.create 16 in
  List.iter
    (function
      | Ast.IFunc f ->
          let ptypes = List.map (fun (pr : Ast.param) -> ty_of_name pr.Ast.ptype) f.Ast.params in
          Hashtbl.replace funcs f.Ast.fname (ptypes, ret_of f)
      | _ -> ())
    prog.Ast.items;
  let funcdefs =
    List.filter_map
      (function
        | Ast.IFunc f ->
            let params = List.map (fun (pr : Ast.param) -> (pr.Ast.pname, ty_of_name pr.Ast.ptype)) f.Ast.params in
            Some (lower_func structs enums funcs f.Ast.fname params (ret_of f) f.Ast.body)
        | _ -> None)
      prog.Ast.items
  in
  let main_body = List.filter_map (function Ast.IStmt s -> Some s | _ -> None) prog.Ast.items in
  let main = lower_func structs enums funcs "main" [] Types.TVoid main_body in
  let struct_layouts =
    List.filter_map (function Ast.IStruct s -> Some (Hashtbl.find structs s.Ast.sname) | _ -> None) prog.Ast.items
  in
  let enum_layouts =
    List.filter_map (function Ast.IEnum e -> Some (Hashtbl.find enums e.Ast.ename) | _ -> None) prog.Ast.items
  in
  { Sil.funcs = funcdefs @ [ main ]; structs = struct_layouts; enums = enum_layouts }
