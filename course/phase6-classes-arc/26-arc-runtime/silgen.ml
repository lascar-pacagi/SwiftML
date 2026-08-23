(* FROZEN SOLUTION — concept 26 SILGen: ARC insertion (ownership, scopes, temps) + destructors. *)

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
  protos : (string, Types.proto_layout) Hashtbl.t; (* concept 21 *)
  methods : (string, (string * Types.ty list * Types.ty) list) Hashtbl.t; (* concept 21: struct -> method sigs *)
  gfuncs : (string, (string * string) list * Types.ty list * Types.ty) Hashtbl.t;
    (* concept 22: generic functions — (type params w/ constraints, param tys w/ TVar, ret) *)
  classes : (string, Types.class_layout) Hashtbl.t; (* concept 25 *)
  ret : Types.ty; (* the enclosing function's return type — for return-wrapping (concept 13) *)
  mutable loops : (int * int * int) list;
    (* stack of (continue-target, break-target, scope depth at loop entry) — the depth lets
       break/continue release the scopes they jump out of (concept 26) *)
  (* ARC state — concept 26 *)
  owned : (Sil.value, unit) Hashtbl.t;
    (* class-typed values carrying +1 (fresh allocations, owned call results) that some
       consumer must balance: a slot store consumes it, otherwise it's released at the end
       of its statement *)
  mutable scopes : Sil.value list ref list;
    (* stack of scopes, innermost first; each holds the class-typed slot ADDRESSES declared
       there (in declaration order — released in reverse at scope exit) *)
  mutable stmt_temps : Sil.value list; (* owned temps of the current statement *)
  mutable in_init : bool; (* field stores in an init don't release the (garbage) old value *)
}

(* --- the builder API (given) --- *)
let emit (b : builder) (instr : Sil.instr) (ty : Types.ty) : Sil.value =
  let v = b.next_val in
  b.next_val <- v + 1;
  b.cur.Sil.instrs <- (v, instr) :: b.cur.Sil.instrs;
  Hashtbl.replace b.val_ty v ty;
  v

let new_block (b : builder) : Sil.block =
  let blk = { Sil.bid = b.next_block; args = []; instrs = []; term = Sil.Unreachable } in
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
        else if Hashtbl.mem b.protos name then Types.TProto name (* concept 21 *)
        else if Hashtbl.mem b.classes name then Types.TClass name (* concept 25 *)
        else Types.TInt (* includes T inside a generic body: erased via the param types below *)

let is_nil = function Ast.Nil _ -> true | _ -> false

(* ---- ARC helpers (concept 26) ---- *)
let is_class_ty = function Types.TClass _ -> true | _ -> false

(* a fresh +1 value (allocation / owned call result): track it as a statement temp *)
let mark_owned (b : builder) (v : Sil.value) : Sil.value =
  if is_class_ty (Hashtbl.find b.val_ty v) then begin
    Hashtbl.replace b.owned v ();
    b.stmt_temps <- v :: b.stmt_temps
  end;
  v

(* a value is about to be STORED somewhere durable: take ownership. An owned temp transfers
   (consume: it's no longer the statement's to release); a borrowed value gets a retain. *)
let take_ownership (b : builder) (v : Sil.value) : unit =
  (* TODO(26a): the ownership-transfer rule — a store either CONSUMES a fresh +1 temp or
       RETAINS a borrowed value, and nothing else. Get it wrong one way and objects die early;
       the other way and they leak with their deinit never firing. The deinit-order probes catch
       both. §2. *)
  ignore (b, v);
  failwith "TODO(26a-silgen): consume an owned temp / retain a borrowed value"

(* end of statement: release the owned temps nobody consumed *)
let release_stmt_temps (b : builder) : unit =
  List.iter (fun v -> ignore (emit b (Sil.Release v) Types.TVoid)) b.stmt_temps;
  List.iter (fun v -> Hashtbl.remove b.owned v) b.stmt_temps;
  b.stmt_temps <- []

(* release the class-typed locals of one scope, newest first *)
let release_scope (b : builder) (slots : Sil.value list) : unit =
  List.iter
    (fun slot ->
      let v = emit b (Sil.Load slot) (Hashtbl.find b.val_ty slot) in
      ignore (emit b (Sil.Release v) Types.TVoid))
    slots

let push_scope (b : builder) = b.scopes <- ref [] :: b.scopes
let pop_scope_release (b : builder) =
  (match b.scopes with sc :: rest -> release_scope b !sc; b.scopes <- rest | [] -> ())
let register_local (b : builder) (slot : Sil.value) =
  if is_class_ty (Hashtbl.find b.val_ty slot) then
    match b.scopes with sc :: _ -> sc := slot :: !sc | [] -> ()

(* releases for a NON-LOCAL exit (return / break / continue): emit releases for every scope
   deeper than [down_to] (without popping — the structured path still needs them) *)
let release_down_to (b : builder) (down_to : int) : unit =
  let depth = List.length b.scopes in
  List.iteri (fun i sc -> if depth - i > down_to then release_scope b !sc) b.scopes

(* concept 21: a method's signature, and the struct we're inside (a method body's `self`
   parameter slot is named "self" — if it exists, bare field/method names resolve through it) *)
let method_sig (b : builder) (sname : string) (m : string) : (Types.ty list * Types.ty) option =
  Option.bind (Hashtbl.find_opt b.methods sname) (fun ms ->
      List.find_map (fun (n, ps, r) -> if n = m then Some (ps, r) else None) ms)

let self_class (b : builder) : string option =
  match Hashtbl.find_opt b.vars "self" with
  | Some slot -> ( match Hashtbl.find b.val_ty slot with Types.TClass cn -> Some cn | _ -> None)
  | None -> None

let self_struct (b : builder) : string option =
  match Hashtbl.find_opt b.vars "self" with
  | Some slot -> ( match Hashtbl.find b.val_ty slot with Types.TStruct sn -> Some sn | _ -> None)
  | None -> None

(* --- lowering expressions: returns the SIL value holding the result --- *)
let rec gen_expr (b : builder) (e : Ast.expr) : Sil.value =
  match e with
  | Ast.Int_lit (n, _) -> emit b (Sil.Int_lit n) Types.TInt
  | Ast.Double_lit (f, _) -> emit b (Sil.Float_lit f) Types.TDouble
  | Ast.Bool_lit (x, _) -> emit b (Sil.Bool_lit x) Types.TBool
  | Ast.String_lit (s, _) -> emit b (Sil.String_lit s) Types.TString
  | Ast.Var (x, _) -> (
      match Hashtbl.find_opt b.vars x with
      | Some addr -> emit b (Sil.Load addr) (vty b addr) (* the slot's element type *)
      | None -> (
          match self_class b with
          | Some cn ->
              (* a bare name in a CLASS method/init: load the field through the self REFERENCE *)
              let cl = Hashtbl.find b.classes cn in
              let selfv = emit b (Sil.Load (Hashtbl.find b.vars "self")) (Types.TClass cn) in
              let fa = emit b (Sil.Ref_element_addr (selfv, Option.get (Types.cfield_index cl x)))
                         (Option.get (Types.cfield_type cl x)) in
              emit b (Sil.Load fa) (Option.get (Types.cfield_type cl x))
          | None ->
              (* inside a struct method, a bare name is a stored property: `r` = `self.r` (21) *)
              let sn = Option.get (self_struct b) in
              let sl = Hashtbl.find b.structs sn in
              let selfv = emit b (Sil.Load (Hashtbl.find b.vars "self")) (Types.TStruct sn) in
              emit b (Sil.Struct_extract (selfv, Option.get (Types.field_index sl x)))
                (Option.get (Types.field_type sl x))))
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
      terminate b (Sil.Cond_br (lv, (t_tgt, []), (f_tgt, [])));
      switch_to b rhs_b;
      let rv = gen_expr b r in
      ignore (emit b (Sil.Store (rv, slot)) Types.TVoid);
      terminate b (Sil.Br (merge.Sil.bid, []));
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
      if Hashtbl.mem b.classes f then (
        (* a class CONSTRUCTOR (concept 25): heap-allocate (the header gets the class's vtable
           pointer and an initial refcount), then run the declared initializer on the reference *)
        let refv = emit b (Sil.Alloc_ref f) (Types.TClass f) in
        let rec init_owner cn =
          if Hashtbl.mem b.funcs (cn ^ ".init") then Some cn
          else match (Hashtbl.find b.classes cn).Types.cl_super with
            | Some s -> init_owner s
            | None -> None
        in
        (match init_owner f with
        | Some owner ->
            let ptys, _ = Hashtbl.find b.funcs (owner ^ ".init") in
            let argvs = List.map2 (fun (_, e) pt -> gen_expr_as b e pt) args ptys in
            let selfv = if owner = f then refv else emit b (Sil.Upcast (refv, owner)) (Types.TClass owner) in
            let fr = emit b (Sil.Func_ref (owner ^ ".init")) Types.TVoid in
            ignore (emit b (Sil.Apply (fr, selfv :: argvs)) Types.TVoid)
        | None -> ());
        mark_owned b refv)
      else if Hashtbl.mem b.structs f then (
        (* a struct field may be optional, so wrap each argument to its field type *)
        let sl = Hashtbl.find b.structs f in
        let argvs = List.map2 (fun (_, e) (_, ft) -> gen_expr_as b e ft) args sl.Types.sl_fields in
        emit b (Sil.Struct argvs) (Types.TStruct f))
      else if Hashtbl.mem b.funcs f then (
        let ptypes, ret = Hashtbl.find b.funcs f in
        let argvs = List.map2 (fun (_, e) pt -> gen_expr_as b e pt) args ptypes in
        let fr = emit b (Sil.Func_ref f) ret in
        (* a class-typed result comes back +1 (owned) — the callee retained it for us (26) *)
        mark_owned b (emit b (Sil.Apply (fr, argvs)) ret))
      else if Hashtbl.mem b.gfuncs f then (
        (* a call to a GENERIC function — concept 22. The function is compiled ONCE with every
           `T` erased to its constraint's existential, so the call site (a) WRAPS each argument
           in a T position (a concrete struct becomes an existential; an already-erased value
           passes through), and (b) OPENS the result if the declared return is T and the
           inferred T is concrete — the caller knows the type statically, so the open is
           checked-by-construction. *)
        let generics, ptypes, ret = Hashtbl.find b.gfuncs f in
        ignore generics;
        let binding : (string * Types.ty) list ref = ref [] in
        let argvs =
          List.map2
            (fun pt (_, e) ->
              match pt with
              | Types.TVar (n, c) -> (
                  let v = gen_expr b e in
                  if not (List.mem_assoc n !binding) then binding := (n, vty b v) :: !binding;
                  match vty b v with
                  | Types.TProto _ -> v (* already erased (a generic calling a generic) *)
                  | Types.TStruct sn -> emit b (Sil.Init_existential (v, sn, c)) (Types.TProto c)
                  | _ -> assert false (* sema enforced the constraint *))
              | _ -> gen_expr_as b e pt)
            ptypes args
        in
        let erased_ret = match ret with Types.TVar (_, c) -> Types.TProto c | t -> t in
        let fr = emit b (Sil.Func_ref f) erased_ret in
        let callv = emit b (Sil.Apply (fr, argvs)) erased_ret in
        match ret with
        | Types.TVar (n, _) -> (
            match List.assoc_opt n !binding with
            | Some (Types.TStruct sn) -> emit b (Sil.Open_existential (callv, sn)) (Types.TStruct sn)
            | _ -> callv (* generic-from-generic: stays erased *))
        | _ -> callv)
      else if (match self_class b with
               | Some cn -> Types.vslot (Hashtbl.find b.classes cn) f <> None
               | None -> false) then (
        (* bare `m(args)` in a class method = `self.m(args)` — and it DISPATCHES (an override in
           a subclass wins, even from the superclass's own methods) — concept 25 *)
        let cn = Option.get (self_class b) in
        let cl = Hashtbl.find b.classes cn in
        let slot = Option.get (Types.vslot cl f) in
        let ptypes, ret = Option.get (Types.vsig cl f) in
        let selfv = emit b (Sil.Load (Hashtbl.find b.vars "self")) (Types.TClass cn) in
        let argvs = List.map2 (fun (_, e) pt -> gen_expr_as b e pt) args ptypes in
        emit b (Sil.Apply_class (selfv, slot, argvs)) ret)
      else (
        match Option.bind (self_struct b) (fun sn -> Option.map (fun sg -> (sn, sg)) (method_sig b sn f)) with
        | Some (sn, (ptypes, ret)) ->
            (* bare `m(args)` in a method = `self.m(args)`: a DIRECT call to @S.m (concept 21) *)
            let selfv = emit b (Sil.Load (Hashtbl.find b.vars "self")) (Types.TStruct sn) in
            let argvs = List.map2 (fun (_, e) pt -> gen_expr_as b e pt) args ptypes in
            let fr = emit b (Sil.Func_ref (sn ^ "." ^ f)) ret in
            emit b (Sil.Apply (fr, selfv :: argvs)) ret
        | None ->
            let argvs = List.map (fun (_, e) -> gen_expr b e) args in
            emit b (Sil.Print (List.hd argvs)) Types.TVoid)
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
      | Types.TClass cn ->
          (* a field read through a REFERENCE: address the field in the heap object, load (25) *)
          let cl = Hashtbl.find b.classes cn in
          let ft = Option.get (Types.cfield_type cl fld) in
          let fa = emit b (Sil.Ref_element_addr (sv, Option.get (Types.cfield_index cl fld))) ft in
          emit b (Sil.Load fa) ft
      | _ -> assert false)
  (* `E.case(args)` — a payload-carrying enum case (concept 11) *)
  | Ast.Method_call (Ast.Var (tn, _), case, args, _) when Hashtbl.mem b.enums tn ->
      let el = Hashtbl.find b.enums tn in
      let argvs = List.map (fun (_, e) -> gen_expr b e) args in
      emit b (Sil.Enum (Option.get (Types.case_index el case), argvs)) (Types.TEnum tn)
  (* `super.init(args)` — a DIRECT (static) call to the superclass initializer (concept 25) *)
  | Ast.Method_call (Ast.Var ("super", _), "init", args, _) ->
      let cn = Option.get (self_class b) in
      let sup = Option.get (Hashtbl.find b.classes cn).Types.cl_super in
      let selfv = emit b (Sil.Load (Hashtbl.find b.vars "self")) (Types.TClass cn) in
      let ptys, _ = Hashtbl.find b.funcs (sup ^ ".init") in
      let argvs = List.map2 (fun (_, e) pt -> gen_expr_as b e pt) args ptys in
      let upv = emit b (Sil.Upcast (selfv, sup)) (Types.TClass sup) in
      let fr = emit b (Sil.Func_ref (sup ^ ".init")) Types.TVoid in
      emit b (Sil.Apply (fr, upv :: argvs)) Types.TVoid
  (* `recv.m(args)` — concept 21. On a concrete struct: a DIRECT (static) call to @S.m with
     self as the first argument. On an existential: DYNAMIC dispatch through the witness
     table (`Apply_witness` = swiftc's witness_method+apply). *)
  | Ast.Method_call (recv, m, args, _) -> (
      let rv = gen_expr b recv in
      match vty b rv with
      | Types.TStruct sn ->
          let ptypes, ret = Option.get (method_sig b sn m) in
          let argvs = List.map2 (fun (_, e) pt -> gen_expr_as b e pt) args ptypes in
          let fr = emit b (Sil.Func_ref (sn ^ "." ^ m)) ret in
          emit b (Sil.Apply (fr, rv :: argvs)) ret
      | Types.TProto pn ->
          let pl = Hashtbl.find b.protos pn in
          let slot = Option.get (Types.req_index pl m) in
          let ptypes, ret = Option.get (Types.req_sig pl m) in
          let argvs = List.map2 (fun (_, e) pt -> gen_expr_as b e pt) args ptypes in
          emit b (Sil.Apply_witness (rv, slot, argvs)) ret
      | Types.TClass cn ->
          (* DYNAMIC dispatch through the VTABLE (concept 25): the slot is fixed by the STATIC
             type's layout; the function pointer comes from the OBJECT's vtable — an override
             in the dynamic type wins. *)
          let cl = Hashtbl.find b.classes cn in
          let slot = Option.get (Types.vslot cl m) in
          let ptypes, ret = Option.get (Types.vsig cl m) in
          let argvs = List.map2 (fun (_, e) pt -> gen_expr_as b e pt) args ptypes in
          mark_owned b (emit b (Sil.Apply_class (rv, slot, argvs)) ret)
      | _ -> assert false (* sema rejected it *))
  (* optionals are an enum { none(tag 0); some(tag 1, payload) } — concept 13 *)
  | Ast.Nil _ -> assert false (* nil only appears in a checked context; gen_expr_as handles it *)
  | Ast.Force_unwrap (e0, _) ->
      let ov = gen_expr b e0 in
      let t = match vty b ov with Types.TOptional t -> t | _ -> assert false in
      let tag = emit b (Sil.Enum_tag ov) Types.TInt in
      let one = emit b (Sil.Int_lit 1) Types.TInt in
      let c = emit b (Sil.Binop (Ast.Eq, tag, one)) Types.TBool in
      let cont_b = new_block b and trap_b = new_block b in
      terminate b (Sil.Cond_br (c, (cont_b.Sil.bid, []), (trap_b.Sil.bid, [])));
      switch_to b trap_b;
      terminate b (Sil.Trap "Fatal error: Unexpectedly found nil while unwrapping an Optional value");
      switch_to b cont_b;
      emit b (Sil.Enum_payload (ov, 0)) t
  (* `e as? T` / `e as! T` — concept 23. Both test TYPE IDENTITY via the witness-table
     pointer (same_witness), then OPEN the payload in the branch where it's proven right:
       as?  ->  same ? .some(open e) : .none        (an Optional<T> built across a diamond)
       as!  ->  same ? open e        : abort        (swiftc aborts: exit 134)            *)
  | Ast.Cast (e0, tyname, conditional, _) ->
      let ev = gen_expr b e0 in
      let sn = tyname in
      (* a cast to a NON-conforming type has no witness table to compare against — it is
         statically always-false (sema already warned, like swiftc) *)
      let conforms =
        match vty b ev with
        | Types.TProto pn | Types.TVar (_, pn) -> (
            match Hashtbl.find_opt b.protos pn with
            | Some pl ->
                List.for_all
                  (fun (rn, rps, rret) ->
                    match method_sig b sn rn with Some (ps, r) -> ps = rps && r = rret | None -> false)
                  pl.Types.pl_reqs
            | None -> false)
        | _ -> false
      in
      let same =
        if conforms then emit b (Sil.Same_witness (ev, sn)) Types.TBool
        else emit b (Sil.Bool_lit false) Types.TBool
      in
      if conditional then (
        let optty = Types.TOptional (Types.TStruct sn) in
        let slot = emit b (Sil.Alloc_stack "cast") optty in
        let yes = new_block b and no = new_block b and merge = new_block b in
        terminate b (Sil.Cond_br (same, (yes.Sil.bid, []), (no.Sil.bid, [])));
        switch_to b yes;
        let pv = emit b (Sil.Open_existential (ev, sn)) (Types.TStruct sn) in
        let somev = emit b (Sil.Enum (1, [ pv ])) optty in
        ignore (emit b (Sil.Store (somev, slot)) Types.TVoid);
        terminate b (Sil.Br (merge.Sil.bid, []));
        switch_to b no;
        let nonev = emit b (Sil.Enum (0, [])) optty in
        ignore (emit b (Sil.Store (nonev, slot)) Types.TVoid);
        terminate b (Sil.Br (merge.Sil.bid, []));
        switch_to b merge;
        emit b (Sil.Load slot) optty)
      else (
        let ok = new_block b and fail = new_block b in
        terminate b (Sil.Cond_br (same, (ok.Sil.bid, []), (fail.Sil.bid, [])));
        switch_to b fail;
        terminate b (Sil.Abort (Printf.sprintf "Could not cast value to '%s'" sn));
        switch_to b ok;
        emit b (Sil.Open_existential (ev, sn)) (Types.TStruct sn))
  (* ternary `c ? a : b` — a value-producing diamond (the general case of `&&`/`||`): evaluate the
     condition, branch, evaluate ONLY the taken arm, merge both arms' results through a slot. *)
  | Ast.Ternary (cnd, te, ee, _) ->
      let cv = gen_expr b cnd in
      let then_b = new_block b and else_b = new_block b and merge = new_block b in
      terminate b (Sil.Cond_br (cv, (then_b.Sil.bid, []), (else_b.Sil.bid, [])));
      switch_to b then_b;
      let tv = gen_expr b te in
      let t = vty b tv in
      let slot = emit b (Sil.Alloc_stack "tern") t in
      ignore (emit b (Sil.Store (tv, slot)) Types.TVoid);
      terminate b (Sil.Br (merge.Sil.bid, []));
      switch_to b else_b;
      let ev = gen_expr_as b ee t in
      ignore (emit b (Sil.Store (ev, slot)) Types.TVoid);
      terminate b (Sil.Br (merge.Sil.bid, []));
      switch_to b merge;
      emit b (Sil.Load slot) t
  | Ast.Coalesce (a, bexpr, _) ->
      (* a ?? b : if a is some, its payload; else b. The result merges two paths, so route both
         into a slot and load it afterwards. *)
      let av = gen_expr b a in
      let t = match vty b av with Types.TOptional t -> t | _ -> assert false in
      let slot = emit b (Sil.Alloc_stack "coalesce") t in
      let tag = emit b (Sil.Enum_tag av) Types.TInt in
      let one = emit b (Sil.Int_lit 1) Types.TInt in
      let c = emit b (Sil.Binop (Ast.Eq, tag, one)) Types.TBool in
      let some_b = new_block b and none_b = new_block b and merge = new_block b in
      terminate b (Sil.Cond_br (c, (some_b.Sil.bid, []), (none_b.Sil.bid, [])));
      switch_to b some_b;
      let pv = emit b (Sil.Enum_payload (av, 0)) t in
      ignore (emit b (Sil.Store (pv, slot)) Types.TVoid);
      terminate b (Sil.Br (merge.Sil.bid, []));
      switch_to b none_b;
      let bv = gen_expr_as b bexpr t in
      ignore (emit b (Sil.Store (bv, slot)) Types.TVoid);
      terminate b (Sil.Br (merge.Sil.bid, []));
      switch_to b merge;
      emit b (Sil.Load slot) t

(* lower `e` where an optional is expected: `nil` -> none; a `T` -> `.some(T)` (implicit wrap);
   an already-optional value passes through — concept 13. Concept 21 adds the existential twin:
   where `any P` is expected, a concrete conforming struct is WRAPPED (`init_existential`
   pairs the value with its witness table); an existing `any P` passes through. *)
and gen_expr_as (b : builder) (e : Ast.expr) (expected : Types.ty) : Sil.value =
  match (e, expected) with
  | Ast.Nil _, Types.TOptional _ -> emit b (Sil.Enum (0, [])) expected
  | _, Types.TOptional _ ->
      let v = gen_expr b e in
      if vty b v = expected then v else emit b (Sil.Enum (1, [ v ])) expected
  | _, Types.TProto pn -> (
      let v = gen_expr b e in
      match vty b v with
      | Types.TProto _ -> v (* already an existential *)
      | Types.TStruct sn -> emit b (Sil.Init_existential (v, sn, pn)) expected
      | _ -> assert false (* sema guaranteed conformance *))
  (* a subclass reference upcasts to its superclass — same pointer, retyped (concept 25) *)
  | _, Types.TClass cn -> (
      let v = gen_expr b e in
      match vty b v with
      | Types.TClass dn when dn = cn -> v
      | Types.TClass _ -> emit b (Sil.Upcast (v, cn)) expected
      | _ -> assert false)
  | _ -> gen_expr b e

(* --- lowering statements; gen_block stops after a terminator (dead code) ---
   ARC (26): every statement releases its unconsumed owned temps when it completes; a block
   is a SCOPE — its class-typed locals are released (newest first) when it falls through.
   Early exits (return/break/continue) emit their own releases before branching. *)
let rec gen_block (b : builder) (stmts : Ast.stmt list) : unit =
  push_scope b;
  gen_stmts b stmts;
  if b.cur.Sil.term = Sil.Unreachable then pop_scope_release b
  else (match b.scopes with _ :: rest -> b.scopes <- rest | [] -> ())

and gen_stmts (b : builder) (stmts : Ast.stmt list) : unit =
  match stmts with
  | [] -> ()
  | s :: rest ->
      gen_stmt b s;
      release_stmt_temps b;
      if b.cur.Sil.term = Sil.Unreachable then gen_stmts b rest

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
      take_ownership b v; (* a class value stored in a local: +1 owned by the slot (26) *)
      let addr = emit b (Sil.Alloc_stack name) slot_ty in
      Hashtbl.replace b.vars name addr;
      register_local b addr;
      ignore (emit b (Sil.Store (v, addr)) Types.TVoid)
  | Ast.Assign { name; value; _ } -> (
      match Hashtbl.find_opt b.vars name with
      | Some slot ->
          (* wrap to the SLOT's type, not the value's: assigning `7` to an `Int?` var must store
             `.some(7)`, and assigning a concrete struct to an `any P` var must re-wrap the
             existential. (A real shipped miscompile: plain gen_expr here stored the raw value —
             caught when concept 21's existential reassignment dispatched through garbage.) *)
          let v = gen_expr_as b value (vty b slot) in
          if is_class_ty (vty b slot) then begin
            (* ARC (26): take the new value (+1), store, THEN release the old — swiftc's
               observable order (the old object's deinit fires after the new one's init) *)
            let old = emit b (Sil.Load slot) (vty b slot) in
            take_ownership b v;
            ignore (emit b (Sil.Store (v, slot)) Types.TVoid);
            ignore (emit b (Sil.Release old) Types.TVoid)
          end
          else ignore (emit b (Sil.Store (v, slot)) Types.TVoid)
      | None ->
          (* a bare field write in a CLASS method/init: store through self (concept 25).
             ARC (26): the field takes ownership; outside an init the old value is released
             (in an init the slot still holds allocation garbage — nothing to release). *)
          let cn = Option.get (self_class b) in
          let cl = Hashtbl.find b.classes cn in
          let ft = Option.get (Types.cfield_type cl name) in
          let v = gen_expr_as b value ft in
          let selfv = emit b (Sil.Load (Hashtbl.find b.vars "self")) (Types.TClass cn) in
          let fa = emit b (Sil.Ref_element_addr (selfv, Option.get (Types.cfield_index cl name))) ft in
          if is_class_ty ft then begin
            take_ownership b v;
            if not b.in_init then begin
              let old = emit b (Sil.Load fa) ft in
              ignore (emit b (Sil.Store (v, fa)) Types.TVoid);
              ignore (emit b (Sil.Release old) Types.TVoid)
            end
            else ignore (emit b (Sil.Store (v, fa)) Types.TVoid)
          end
          else ignore (emit b (Sil.Store (v, fa)) Types.TVoid))
  | Ast.Set_member { obj; field; value; _ } -> (
      let slot = Hashtbl.find b.vars obj in
      match vty b slot with
      | Types.TClass cn ->
          (* `c.x = e` through a REFERENCE: load the pointer, address the field in the heap
             object, store — every binding to the same object sees the write (concept 25).
             ARC (26): class-typed fields take ownership and release what they held. *)
          let cl = Hashtbl.find b.classes cn in
          let ft = Option.get (Types.cfield_type cl field) in
          let v = gen_expr_as b value ft in
          let refv = emit b (Sil.Load slot) (Types.TClass cn) in
          let fa = emit b (Sil.Ref_element_addr (refv, Option.get (Types.cfield_index cl field))) ft in
          if is_class_ty ft then begin
            take_ownership b v;
            if not b.in_init then begin
              let old = emit b (Sil.Load fa) ft in
              ignore (emit b (Sil.Store (v, fa)) Types.TVoid);
              ignore (emit b (Sil.Release old) Types.TVoid)
            end
            else ignore (emit b (Sil.Store (v, fa)) Types.TVoid)
          end
          else ignore (emit b (Sil.Store (v, fa)) Types.TVoid)
      | Types.TStruct sn ->
          (* `p.x = e`: take the field's ADDRESS in p's slot, then store — this is what makes a
             struct a value type, since p has its own slot distinct from any copy *)
          let v = gen_expr b value in
          let sl = Hashtbl.find b.structs sn in
          let faddr =
            emit b (Sil.Struct_element_addr (slot, Option.get (Types.field_index sl field)))
              (Option.get (Types.field_type sl field))
          in
          ignore (emit b (Sil.Store (v, faddr)) Types.TVoid)
      | _ -> assert false)
  | Ast.Expr_stmt (e, _) -> ignore (gen_expr b e)
  | Ast.Return (eo, _) -> (
      match eo with
      | Some e ->
          (* wrap to the function's return type (so `return 5` in a `-> Int?` func returns some(5)) *)
          let v = gen_expr_as b e b.ret in
          (* ARC (26): the caller receives the result at +1. An owned temp transfers; a
             borrowed value (e.g. `return t` of a local about to be released) gets a retain
             FIRST — then every live scope releases, and the +1 survives the cleanup. *)
          take_ownership b v;
          release_stmt_temps b;
          release_down_to b 0;
          terminate b (Sil.Return (Some v))
      | None ->
          release_stmt_temps b;
          release_down_to b 0;
          terminate b (Sil.Return None))
  | Ast.If { cond; then_blk; else_blk; _ } ->
      let c = gen_expr b cond in
      let then_b = new_block b in
      let merge = new_block b in
      let else_b = match else_blk with Some _ -> new_block b | None -> merge in
      terminate b (Sil.Cond_br (c, (then_b.Sil.bid, []), (else_b.Sil.bid, [])));
      switch_to b then_b;
      gen_block b then_blk;
      terminate b (Sil.Br (merge.Sil.bid, []));
      (match else_blk with
      | Some e ->
          switch_to b else_b;
          gen_block b e;
          terminate b (Sil.Br (merge.Sil.bid, []))
      | None -> ());
      switch_to b merge
  | Ast.If_let { name; opt; then_blk; else_blk; _ } ->
      (* `if let x = opt`: if opt is `.some`, bind x to its payload and run then; else run else *)
      let ov = gen_expr b opt in
      let t = match vty b ov with Types.TOptional t -> t | _ -> assert false in
      let tag = emit b (Sil.Enum_tag ov) Types.TInt in
      let one = emit b (Sil.Int_lit 1) Types.TInt in
      let c = emit b (Sil.Binop (Ast.Eq, tag, one)) Types.TBool in
      let then_b = new_block b and merge = new_block b in
      let else_b = match else_blk with Some _ -> new_block b | None -> merge in
      terminate b (Sil.Cond_br (c, (then_b.Sil.bid, []), (else_b.Sil.bid, [])));
      switch_to b then_b;
      let pv = emit b (Sil.Enum_payload (ov, 0)) t in
      let addr = emit b (Sil.Alloc_stack name) t in
      Hashtbl.replace b.vars name addr;
      ignore (emit b (Sil.Store (pv, addr)) Types.TVoid);
      gen_block b then_blk;
      terminate b (Sil.Br (merge.Sil.bid, []));
      (match else_blk with
      | Some e -> switch_to b else_b; gen_block b e; terminate b (Sil.Br (merge.Sil.bid, []))
      | None -> ());
      switch_to b merge
  | Ast.While { cond; body; _ } ->
      let header = new_block b and body_b = new_block b and exit_b = new_block b in
      terminate b (Sil.Br (header.Sil.bid, []));
      switch_to b header;
      let c = gen_expr b cond in
      terminate b (Sil.Cond_br (c, (body_b.Sil.bid, []), (exit_b.Sil.bid, [])));
      switch_to b body_b;
      b.loops <- (header.Sil.bid, exit_b.Sil.bid, List.length b.scopes) :: b.loops;
      gen_block b body;
      terminate b (Sil.Br (header.Sil.bid, []));
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
      terminate b (Sil.Br (header.Sil.bid, []));
      switch_to b header;
      let cur_v = emit b (Sil.Load addr) Types.TInt in
      let c = emit b (Sil.Binop (Ast.Lt, cur_v, hiv)) Types.TBool in
      terminate b (Sil.Cond_br (c, (body_b.Sil.bid, []), (exit_b.Sil.bid, [])));
      switch_to b body_b;
      b.loops <- (latch.Sil.bid, exit_b.Sil.bid, List.length b.scopes) :: b.loops;
      gen_block b body;
      terminate b (Sil.Br (latch.Sil.bid, []));
      b.loops <- List.tl b.loops;
      switch_to b latch;
      let cv = emit b (Sil.Load addr) Types.TInt in
      let one = emit b (Sil.Int_lit 1) Types.TInt in
      let inc = emit b (Sil.Binop (Ast.Add, cv, one)) Types.TInt in
      ignore (emit b (Sil.Store (inc, addr)) Types.TVoid);
      terminate b (Sil.Br (header.Sil.bid, []));
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
            | Some body -> gen_block b body; terminate b (Sil.Br (merge.Sil.bid, []))
            | None -> terminate b Sil.Unreachable (* an exhaustive enum switch: no case left *))
        | (pat, body) :: rest ->
            let k = emit b (Sil.Int_lit (key_of pat)) Types.TInt in
            let c = emit b (Sil.Binop (Ast.Eq, disc, k)) Types.TBool in
            let case_b = new_block b and next_b = new_block b in
            terminate b (Sil.Cond_br (c, (case_b.Sil.bid, []), (next_b.Sil.bid, [])));
            switch_to b case_b;
            bind_payload pat;
            gen_block b body;
            terminate b (Sil.Br (merge.Sil.bid, []));
            switch_to b next_b;
            dispatch rest
      in
      dispatch cases;
      switch_to b merge
  | Ast.Break _ -> (
      match b.loops with
      | (_, ex, depth) :: _ ->
          (* ARC (26): leaving the loop releases the scopes inside it *)
          release_stmt_temps b;
          release_down_to b depth;
          terminate b (Sil.Br (ex, []))
      | [] -> ())
  | Ast.Continue _ -> (
      match b.loops with
      | (cont, _, depth) :: _ ->
          release_stmt_temps b;
          release_down_to b depth;
          terminate b (Sil.Br (cont, []))
      | [] -> ())

(* --- lowering a function: params get slots; then the body --- *)
let lower_func ?(generic = false) ?(init = false) ?(epilogue : (builder -> unit) option)
    structs enums protos methods funcs gfuncs classes (name : string)
    (params : (string * Types.ty) list) (ret : Types.ty) (body : Ast.stmt list) : Sil.func =
  let val_ty = Hashtbl.create 16 in
  let entry = { Sil.bid = 0; args = []; instrs = []; term = Sil.Unreachable } in
  let b =
    { next_val = 0; next_block = 1; cur = entry; blocks = [ entry ]; vars = Hashtbl.create 16; val_ty; funcs; structs; enums; protos; methods; gfuncs; classes; ret; loops = [];
      owned = Hashtbl.create 16; scopes = []; stmt_temps = []; in_init = init }
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
  push_scope b;
  gen_stmts b body;
  if b.cur.Sil.term = Sil.Unreachable then begin
    (* `main`'s top-level variables are GLOBALS: swiftc never runs their deinits at process
       exit, and neither do we — pop without releasing (concept 26) *)
    (if name = "main" then (match b.scopes with _ :: rest -> b.scopes <- rest | [] -> ())
     else pop_scope_release b);
    (match epilogue with Some f -> f b | None -> ())
  end;
  terminate b (if ret = Types.TVoid then Sil.Return None else Sil.Unreachable);
  { Sil.fname = name; params = sil_params; ret; generic; blocks = b.blocks; val_ty }

(* --- the entry point: a checked program -> a SIL module --- *)
let lower (prog : Ast.program) : Sil.modul =
  (* struct + enum registries first (names, then layouts) so any type name resolves *)
  let structs : (string, Types.struct_layout) Hashtbl.t = Hashtbl.create 16 in
  let enums : (string, Types.enum_layout) Hashtbl.t = Hashtbl.create 16 in
  let protos : (string, Types.proto_layout) Hashtbl.t = Hashtbl.create 16 in
  let classes : (string, Types.class_layout) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (function
      | Ast.IStruct s -> Hashtbl.replace structs s.Ast.sname { Types.sl_name = s.Ast.sname; sl_fields = [] }
      | Ast.IEnum e -> Hashtbl.replace enums e.Ast.ename { Types.el_name = e.Ast.ename; el_cases = []; el_raw = e.Ast.eraw <> None }
      | Ast.IProto pr -> Hashtbl.replace protos pr.Ast.pname { Types.pl_name = pr.Ast.pname; pl_reqs = [] }
      | Ast.IClass c ->
          Hashtbl.replace classes c.Ast.cname
            { Types.cl_name = c.Ast.cname; cl_super = c.Ast.csuper; cl_fields = []; cl_methods = []; cl_impls = [] }
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
          else if Hashtbl.mem protos n then Types.TProto n
          else if Hashtbl.mem classes n then Types.TClass n (* concept 25 *)
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
      | Ast.IProto pr ->
          let reqs =
            List.map
              (fun (r : Ast.proto_req) ->
                let ps = List.map (fun (p : Ast.param) -> ty_of_name p.Ast.ptype) r.Ast.rparams in
                let ret = match r.Ast.rret with None -> Types.TVoid | Some n -> ty_of_name n in
                (r.Ast.rname, ps, ret))
              pr.Ast.reqs
          in
          Hashtbl.replace protos pr.Ast.pname { Types.pl_name = pr.Ast.pname; pl_reqs = reqs }
      | _ -> ())
    prog.Ast.items;
  (* class layouts — superclass-first, vtable slots inherited/overridden/appended (concept 25).
     The NAME must be registered before ty_of_name resolves any field/param type, so the table
     is declared with the other registries above; here we fill the layouts. *)
  let class_decls = List.filter_map (function Ast.IClass c -> Some c | _ -> None) prog.Ast.items in
  let filled : (string, unit) Hashtbl.t = Hashtbl.create 8 in
  let rec build_class (c : Ast.class_decl) : unit =
    if not (Hashtbl.mem filled c.Ast.cname) then begin
      Hashtbl.replace filled c.Ast.cname ();
      let super_layout =
        match c.Ast.csuper with
        | Some sup ->
            (match List.find_opt (fun (d : Ast.class_decl) -> d.Ast.cname = sup) class_decls with
            | Some sd -> build_class sd
            | None -> ());
            Hashtbl.find_opt classes sup
        | None -> None
      in
      let inherited = match super_layout with Some sl -> sl.Types.cl_fields | None -> [] in
      let own = List.map (fun (fl : Ast.field) -> (fl.Ast.fld_name, ty_of_name fl.Ast.fld_ty)) c.Ast.cfields in
      let methods = ref (match super_layout with Some sl -> sl.Types.cl_methods | None -> []) in
      let impls = ref (match super_layout with Some sl -> sl.Types.cl_impls | None -> []) in
      List.iter
        (fun (_, (m : Ast.func_decl)) ->
          let ps = List.map (fun (p : Ast.param) -> ty_of_name p.Ast.ptype) m.Ast.params in
          let ret = match m.Ast.ret with None -> Types.TVoid | Some n -> ty_of_name n in
          let slot =
            let rec go i = function (n, _, _) :: _ when n = m.Ast.fname -> Some i | _ :: tl -> go (i + 1) tl | [] -> None in
            go 0 !methods
          in
          match slot with
          | Some i -> impls := List.mapi (fun j fn -> if j = i then c.Ast.cname ^ "." ^ m.Ast.fname else fn) !impls
          | None ->
              methods := !methods @ [ (m.Ast.fname, ps, ret) ];
              impls := !impls @ [ c.Ast.cname ^ "." ^ m.Ast.fname ])
        c.Ast.cmethods;
      Hashtbl.replace classes c.Ast.cname
        { Types.cl_name = c.Ast.cname; cl_super = c.Ast.csuper; cl_fields = inherited @ own;
          cl_methods = !methods; cl_impls = !impls }
    end
  in
  List.iter build_class class_decls;
  (* per-struct method signatures (concept 21) *)
  let methods : (string, (string * Types.ty list * Types.ty) list) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (function
      | Ast.IStruct st ->
          let sigs =
            List.map
              (fun (m : Ast.func_decl) ->
                let ps = List.map (fun (p : Ast.param) -> ty_of_name p.Ast.ptype) m.Ast.params in
                let ret = match m.Ast.ret with None -> Types.TVoid | Some n -> ty_of_name n in
                (m.Ast.fname, ps, ret))
              st.Ast.smethods
          in
          Hashtbl.replace methods st.Ast.sname sigs
      | _ -> ())
    prog.Ast.items;
  let ret_of f = match f.Ast.ret with None -> Types.TVoid | Some n -> ty_of_name n in
  (* concept 22: a generic function's parameter/return types mention its type parameters; we
     resolve them against the function's OWN generics (T -> TVar) for the signature table *)
  let gty_of generics n =
    match List.assoc_opt n generics with
    | Some (Some c) -> Types.TVar (n, c)
    | _ -> ty_of_name n
  in
  let funcs = Hashtbl.create 16 in
  let gfuncs = Hashtbl.create 16 in
  List.iter
    (function
      | Ast.IClass c ->
          (match c.Ast.cinit with
          | Some init ->
              let ptys = List.map (fun (p : Ast.param) -> ty_of_name p.Ast.ptype) init.Ast.params in
              Hashtbl.replace funcs (c.Ast.cname ^ ".init") (ptys, Types.TVoid)
          | None -> ());
          List.iter
            (fun (_, (m : Ast.func_decl)) ->
              let ptys = List.map (fun (p : Ast.param) -> ty_of_name p.Ast.ptype) m.Ast.params in
              let ret = match m.Ast.ret with None -> Types.TVoid | Some n -> ty_of_name n in
              Hashtbl.replace funcs (c.Ast.cname ^ "." ^ m.Ast.fname) (ptys, ret))
            c.Ast.cmethods
      | Ast.IFunc f when f.Ast.generics <> [] ->
          let gs = List.filter_map (fun (n, c) -> Option.map (fun c -> (n, c)) c) f.Ast.generics in
          let ptypes = List.map (fun (pr : Ast.param) -> gty_of f.Ast.generics pr.Ast.ptype) f.Ast.params in
          let ret = match f.Ast.ret with None -> Types.TVoid | Some n -> gty_of f.Ast.generics n in
          Hashtbl.replace gfuncs f.Ast.fname (gs, ptypes, ret)
      | Ast.IFunc f ->
          let ptypes = List.map (fun (pr : Ast.param) -> ty_of_name pr.Ast.ptype) f.Ast.params in
          Hashtbl.replace funcs f.Ast.fname (ptypes, ret_of f)
      | _ -> ())
    prog.Ast.items;
  let erase = function Types.TVar (_, c) -> Types.TProto c | t -> t in
  let funcdefs =
    List.concat_map
      (function
        | Ast.IFunc f when f.Ast.generics <> [] ->
            (* the UNSPECIALIZED lowering — concept 22: ONE copy of the body, with every `T`
               erased to its constraint's existential. Method calls on T-typed values inside
               are already witness dispatch (the vty is TProto). Specialization (cloning per
               concrete type) is concept 24's optimization. *)
            let _, ptys, ret = Hashtbl.find gfuncs f.Ast.fname in
            let params = List.map2 (fun (pr : Ast.param) pt -> (pr.Ast.pname, erase pt)) f.Ast.params ptys in
            [ lower_func ~generic:true structs enums protos methods funcs gfuncs classes f.Ast.fname params (erase ret) f.Ast.body ]
        | Ast.IFunc f ->
            let params = List.map (fun (pr : Ast.param) -> (pr.Ast.pname, ty_of_name pr.Ast.ptype)) f.Ast.params in
            [ lower_func structs enums protos methods funcs gfuncs classes f.Ast.fname params (ret_of f) f.Ast.body ]
        | Ast.IClass c ->
            (* the init and each method lower to plain functions with `self : C` (a REFERENCE)
               as the first parameter; the vtable points at these (concept 25) *)
            let self_param = ("self", Types.TClass c.Ast.cname) in
            let lower_m ?(init = false) ?epilogue (m : Ast.func_decl) =
              let params =
                self_param :: List.map (fun (pr : Ast.param) -> (pr.Ast.pname, ty_of_name pr.Ast.ptype)) m.Ast.params
              in
              lower_func ~init ?epilogue structs enums protos methods funcs gfuncs classes
                (c.Ast.cname ^ "." ^ m.Ast.fname) params (ret_of m) m.Ast.body
            in
            (* the DESTRUCTORS (concept 26) — swiftc's deallocation order, verified by probe:
                 1. ALL deinit BODIES run, derived -> base   (`C.deinit`, vtable slot 0)
                 2. then ALL class-typed fields release, base -> derived (`C.destroy`, slot 1)
                 3. then the runtime frees the object once.
               Each chain is entered through the object's vtable (most-derived first) and
               walks up via DIRECT super calls. *)
            let cl = Hashtbl.find classes c.Ast.cname in
            let inherited =
              match cl.Types.cl_super with
              | Some sup -> List.length (Hashtbl.find classes sup).Types.cl_fields
              | None -> 0
            in
            let body_epilogue (b : builder) =
              match cl.Types.cl_super with
              | Some sup ->
                  let selfv = emit b (Sil.Load (Hashtbl.find b.vars "self")) (Types.TClass c.Ast.cname) in
                  let upv = emit b (Sil.Upcast (selfv, sup)) (Types.TClass sup) in
                  let fr = emit b (Sil.Func_ref (sup ^ ".deinit")) Types.TVoid in
                  ignore (emit b (Sil.Apply (fr, [ upv ])) Types.TVoid)
              | None -> ()
            in
            let destroy_epilogue (b : builder) =
              (* TODO(26b): the FIELD-DESTROY chain (slot 1) — superclass FIRST, then this class's own
                 class-typed fields. That is the opposite direction from the deinit-body chain
                 above, and it is not a guess: §2 shows the swiftc output that settles the order. *)
              ignore (b, cl, inherited);
              failwith "TODO(26b-silgen): super-first field destruction, then own fields"
            in
            let dtor =
              lower_m ~epilogue:body_epilogue
                { Ast.fname = "deinit"; generics = []; params = []; ret = None;
                  body = Option.value c.Ast.cdeinit ~default:[]; fspan = c.Ast.cspan }
            in
            let destroyer =
              lower_m ~epilogue:destroy_epilogue
                { Ast.fname = "destroy"; generics = []; params = []; ret = None; body = []; fspan = c.Ast.cspan }
            in
            (dtor :: destroyer
            :: (match c.Ast.cinit with Some init -> [ lower_m ~init:true init ] | None -> []))

            @ List.map (fun (_, m) -> lower_m m) c.Ast.cmethods
        | Ast.IStruct st ->
            (* each method lowers to a plain function `S.m` whose FIRST parameter is `self` —
               method-call syntax is just a calling convention (concept 21) *)
            List.map
              (fun (m : Ast.func_decl) ->
                let params =
                  ("self", Types.TStruct st.Ast.sname)
                  :: List.map (fun (pr : Ast.param) -> (pr.Ast.pname, ty_of_name pr.Ast.ptype)) m.Ast.params
                in
                lower_func structs enums protos methods funcs gfuncs classes
                  (st.Ast.sname ^ "." ^ m.Ast.fname)
                  params (ret_of m) m.Ast.body)
              st.Ast.smethods
        | _ -> [])
      prog.Ast.items
  in
  let main_body = List.filter_map (function Ast.IStmt s -> Some s | _ -> None) prog.Ast.items in
  let main = lower_func structs enums protos methods funcs gfuncs classes "main" [] Types.TVoid main_body in
  let struct_layouts =
    List.filter_map (function Ast.IStruct s -> Some (Hashtbl.find structs s.Ast.sname) | _ -> None) prog.Ast.items
  in
  let enum_layouts =
    List.filter_map (function Ast.IEnum e -> Some (Hashtbl.find enums e.Ast.ename) | _ -> None) prog.Ast.items
  in
  let proto_layouts =
    List.filter_map (function Ast.IProto pr -> Some (Hashtbl.find protos pr.Ast.pname) | _ -> None) prog.Ast.items
  in
  (* one WITNESS TABLE per (struct, protocol) conformance: the implementing function for each
     requirement, in requirement order — the table IS the proof of conformance (concept 21) *)
  let wtables =
    List.concat_map
      (function
        | Ast.IStruct st ->
            List.map
              (fun pname ->
                let pl = Hashtbl.find protos pname in
                let impls = List.map (fun (rn, _, _) -> st.Ast.sname ^ "." ^ rn) pl.Types.pl_reqs in
                (pname, st.Ast.sname, impls))
              st.Ast.sconforms
        | _ -> [])
      prog.Ast.items
  in
  let class_layouts =
    List.filter_map (function Ast.IClass c -> Some (Hashtbl.find classes c.Ast.cname) | _ -> None) prog.Ast.items
  in
  { Sil.funcs = funcdefs @ [ main ]; structs = struct_layouts; enums = enum_layouts;
    protos = proto_layouts; classes = class_layouts; wtables }
