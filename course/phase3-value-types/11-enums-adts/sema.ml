(* Complete Sema for concept 11: concepts 05–10 plus enums.

   New vs 10: an enum registry alongside the struct registry (PASS 0), case typing
   (`E.case` / `E.case(args)`), `.rawValue` on a `: Int` enum, and the Equatable rule — a
   payload-free enum compares by tag, an associated-value one needs a conformance we do not
   synthesize, so `==` on it is refused exactly as swiftc refuses it.

   Inherited from 10: the struct registry, member typing, the memberwise initializer's
   label/arity/type checks, member assignment (a `var` binding AND a `var` field), and the two
   guards for what the back end can lower — `==` and `print` take the scalar types only.

   Inherited from 07:
     - a function-signature table built in a FIRST PASS (so calls, recursion, and forward
       references all resolve), then bodies checked in a second pass
     - call checking: arity + each argument against its parameter type; result = return type
     - return statements checked against the enclosing function's return type
     - the "missing return" check (a non-Void function must definitely return on every path)
     - functions are self-contained (params + the function table only — no top-level capture)
     - print and Void functions yield () (Types.TVoid) *)

(* As from 05, the checker PRODUCES a `Tast.program`. Enums are the sharpest case: `E.red` and
   `p.x` parse to the SAME tree, so a NAME decides which is which, and Swift's rule is that a
   value binding shadows a type name. The answer is recorded as a `Tast.Enum_case` carrying the
   TAG. PLAN.md §0.1 is the miscompile that came of asking that question twice. *)
let check (prog : Ast.program) (diags : Diagnostics.sink) : Tast.program option =
  let env : (string * (Types.ty * bool)) list ref = ref [] in
  let loop_depth = ref 0 in
  let current_ret : Types.ty option ref = ref None in
  let funcs : (string, Types.ty list * Types.ty) Hashtbl.t = Hashtbl.create 16 in
  let structs : (string, Types.struct_layout) Hashtbl.t = Hashtbl.create 16 in
  let enums : (string, Types.enum_layout) Hashtbl.t = Hashtbl.create 16 in
  let let_fields : (string * string, unit) Hashtbl.t = Hashtbl.create 16 in (* (struct, `let` field) *)
  let err span msg = Diagnostics.error diags span msg in
  let lookup x = List.assoc_opt x !env in
  let bind name v = env := (name, v) :: !env in
  let in_scope (f : unit -> unit) = let saved = !env in f (); env := saved in
  (* resolve a written type name: a builtin (Int/Bool/…), a declared struct, or a declared enum *)
  let resolve_opt name =
    match Types.of_name name with
    | Some t -> Some t
    | None ->
        if Hashtbl.mem structs name then Some (Types.TStruct name)
        else if Hashtbl.mem enums name then Some (Types.TEnum name)
        else None
  in
  let resolve_silent name = Option.value (resolve_opt name) ~default:Types.TInt in
  let resolve_ty span name =
    match resolve_opt name with
    | Some t -> t
    | None ->
        err span (Printf.sprintf "cannot find type '%s' in scope" name);
        Types.TInt
  in

  let mk (e : Tast.expr_kind) (ty : Types.ty) (span : Token.span) : Tast.expr = { Tast.e; ty; span } in
  (* `%` is absent: Swift has no `%` on Double, so a tree containing one can never take it *)
  let rec is_int_literal = function
    | Ast.Int_lit _ -> true
    | Ast.Unary (Ast.Neg, e, _) -> is_int_literal e
    | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div), a, b, _) ->
        is_int_literal a && is_int_literal b
    | _ -> false
  in
  let unify l tl r tr : Types.ty option =
    if Types.equal tl tr then Some tl
    else if is_int_literal l && tr = Types.TDouble then Some Types.TDouble
    else if is_int_literal r && tl = Types.TDouble then Some Types.TDouble
    else None
  in
  let rec infer (e : Ast.expr) : Tast.expr =
    match e with
    | Ast.Int_lit (n, span) -> mk (Tast.Int_lit n) Types.TInt span
    | Ast.Double_lit (f, span) -> mk (Tast.Double_lit f) Types.TDouble span
    | Ast.Bool_lit (b, span) -> mk (Tast.Bool_lit b) Types.TBool span
    | Ast.String_lit (t, span) -> mk (Tast.String_lit t) Types.TString span
    | Ast.Var (x, span) -> (
        match lookup x with
        | Some (t, _) -> mk (Tast.Local x) t span
        | None ->
            err span (Printf.sprintf "cannot find '%s' in scope" x);
            mk (Tast.Local x) Types.TInt span)
    | Ast.Unary (Ast.Neg, e0, span) ->
        let n = infer e0 in
        if not (Types.is_numeric n.Tast.ty) then
          err span
            (Printf.sprintf "unary operator '-' cannot be applied to an operand of type '%s'"
               (Types.string_of_ty n.Tast.ty));
        mk (Tast.Unary (Ast.Neg, n)) n.Tast.ty span
    | Ast.Binary (op, l, r, span) -> infer_binary op l r span
    | Ast.Call (f, args, span) -> infer_call f args span
    (* `e as T`: the type is written, so there is nothing to synthesise — CHECK the
       operand against it. The one arm where `infer` calls `check_expr`. *)
    | Ast.Ascribe (e0, tyname, span) -> (
        match Types.of_name tyname with
        | Some t -> mk (Tast.Coerce (check_expr e0 t)) t span
        | None ->
            err span (Printf.sprintf "cannot find type '%s' in scope" tyname);
            let n = infer e0 in
            mk (Tast.Coerce n) n.Tast.ty span)
    (* `E.case` — a no-payload enum case names a value of the enum type (concept 11).
       The guard asks the VALUE SCOPE FIRST: a local binding shadows a type name, so
       `let Color = 7` makes `Color.red` a member access on an Int, not an enum case. Getting
       that order wrong is PLAN.md §0.1's bug; recording the answer is what stops SILGen from
       having to get it right a second time. *)
    | Ast.Member (Ast.Var (type_name, _), _, _)
      when lookup type_name = None && Hashtbl.mem enums type_name ->
        (* TODO(11e): a payload-free enum case. Note the guard, which is GIVEN and is the whole
           shadowing rule: it asks the VALUE SCOPE FIRST, because a local binding shadows a type
           name — `let Color = 7` makes `Color.red` a member access on an Int. Build a
           `Tast.Enum_case` carrying the case's TAG (its index in the declaration), so that
           nothing downstream has to ask this question again. Diagnose an unknown case, and a
           case that needs arguments. See explainer §3, "Type enum construction". *)
        failwith "TODO(11e): type a payload-free enum case"
    | Ast.Member (receiver, field, span) -> (
        let base = infer receiver in
        let unresolved t =
          err span (Printf.sprintf "value of type '%s' has no member '%s'" t field);
          mk (Tast.Field (base, 0, field)) Types.TInt span
        in
        match base.Tast.ty with
        | Types.TStruct sn -> (
            match Hashtbl.find_opt structs sn with
            | Some sl -> (
                match (Types.field_type sl field, Types.field_index sl field) with
                | Some ft, Some i -> mk (Tast.Field (base, i, field)) ft span
                | _ -> unresolved sn)
            | None -> mk (Tast.Field (base, 0, field)) Types.TInt span)
        (* `e.rawValue` on a raw-value enum yields its Int raw value (concept 11) *)
        | Types.TEnum _ when field = "rawValue" ->
            (* TODO(11f): `.rawValue` is available only on an enum declared with an Int raw
               type, and yields an Int. The resolved node is `Tast.Raw_value`. §3. *)
            failwith "TODO(11f): type rawValue on an enum"
        | t -> unresolved (Types.string_of_ty t))
    (* `E.case(args)` — a payload-carrying enum case. Same shadowing rule as `E.case` above. *)
    | Ast.Method_call (Ast.Var (type_name, _), _, _, _)
      when lookup type_name = None && Hashtbl.mem enums type_name ->
        (* TODO(11e): the same, for a case that carries associated values — check each argument
           against its declared payload type, and record them in the `Tast.Enum_case`. *)
        failwith "TODO(11e): type a payload-carrying enum case"
    | Ast.Method_call (e0, _, _, span) ->
        let n = infer e0 in
        err span "methods are not supported in this subset (Phase 3 v0)";
        mk (Tast.Field (n, 0, "?")) Types.TInt span
  and infer_binary op l r span : Tast.expr =
    let ln = infer l and rn = infer r in
    let tl = ln.Tast.ty and tr = rn.Tast.ty in
    let bad () =
      (* swiftc has two wordings and picks by whether the operands agree:
           1 < "a"      -> cannot be applied to operands of type 'Int' and 'String'
           true < false -> cannot be applied to two 'Bool' operands *)
      err span
        (if tl = tr then
           Printf.sprintf "binary operator '%s' cannot be applied to two '%s' operands"
             (Ast.string_of_binop op) (Types.string_of_ty tl)
         else
           Printf.sprintf "binary operator '%s' cannot be applied to operands of type '%s' and '%s'"
             (Ast.string_of_binop op) (Types.string_of_ty tl) (Types.string_of_ty tr));
      Types.TInt
    in
    let u = unify l tl r tr in
    (* APPLY the solution: a side that flexed is re-checked AT the common type *)
    let ln, rn =
      match u with
      | Some t ->
          ((if Types.equal tl t then ln else check_expr l t),
           if Types.equal tr t then rn else check_expr r t)
      | None -> (ln, rn)
    in
    let result =
      match op with
      | Ast.Add -> (
          match u with
          | Some ((Types.TInt | Types.TDouble) as t) -> t
          | Some Types.TString -> Types.TString
          | _ -> bad ())
      | Ast.Sub | Ast.Mul | Ast.Div -> (
          match u with Some ((Types.TInt | Types.TDouble) as t) -> t | _ -> bad ())
      | Ast.Mod -> ( match u with Some Types.TInt -> Types.TInt | _ -> bad ())
      | Ast.Eq | Ast.Ne -> (
          match u with
          (* a payload-free enum is implicitly Equatable; an associated-value enum needs an
             explicit `: Equatable` conformance (deferred), so swiftc — and we — reject it *)
          | Some (Types.TEnum _) ->
              (* TODO(11f): payload-free enums compare by tag; an enum with an associated value
                 is not Equatable in this subset, and swiftc's wording is pinned by the tests. *)
              failwith "TODO(11f): check enum equality"
          (* a struct would need an Equatable conformance too (concept 10, Exercise 3), and the
             back end has no aggregate compare — swiftc's two-operands wording, from `bad ()` *)
          | Some (Types.TInt | Types.TDouble | Types.TBool | Types.TString) -> Types.TBool
          | _ -> ignore (bad ()); Types.TBool)
      | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge -> (
          match u with
          | Some (Types.TInt | Types.TDouble | Types.TString) -> Types.TBool
          | _ -> ignore (bad ()); Types.TBool)
      | Ast.And | Ast.Or ->
          if tl = Types.TBool && tr = Types.TBool then Types.TBool
          else (ignore (bad ()); Types.TBool)
    in
    mk (Tast.Binary (op, ln, rn)) result span
  and infer_call f args span : Tast.expr =
    (* RESOLUTION: initializer, declared function, print, or unknown — decided once, recorded *)
    let first ns = match ns with n :: _ -> n | [] -> mk (Tast.Int_lit 0) Types.TInt span in
    match Hashtbl.find_opt structs f with
    | Some sl -> infer_init f sl args span (* `Point(x: 1, y: 2)` — memberwise initializer *)
    | None -> (
        let exprs = List.map snd args in
        match Hashtbl.find_opt funcs f with
        | Some (ptypes, ret) ->
            let np = List.length ptypes and na = List.length exprs in
            if np <> na then (
              err span (Printf.sprintf "function '%s' expects %d argument(s) but %d given" f np na);
              mk (Tast.Fn_call (f, List.map infer exprs)) ret span)
            else mk (Tast.Fn_call (f, List.map2 check_expr exprs ptypes)) ret span
        | None ->
            if f = "print" then
              match exprs with
              | [ a ] ->
                  (* IRGen prints the scalar types only; swiftc would print `Point(x: 1, y: 2)`
                     for a struct and `red` for an enum case — a divergence, stated in §2 *)
                  let n = infer a in
                  (match n.Tast.ty with
                  | Types.TInt | Types.TDouble | Types.TBool | Types.TString -> ()
                  | t ->
                      err (Ast.expr_span a)
                        (Printf.sprintf
                           "cannot print a value of type '%s' (only Int, Double, Bool and String)"
                           (Types.string_of_ty t)));
                  mk (Tast.Print n) Types.TVoid span
              | _ ->
                  err span "print(_:) expects exactly one argument";
                  mk (Tast.Print (first (List.map infer exprs))) Types.TVoid span
            else (
              err span (Printf.sprintf "cannot find '%s' in scope" f);
              mk (Tast.Print (first (List.map infer exprs))) Types.TInt span))
  (* the memberwise initializer: one labeled argument per stored property, in order. The labels
     are checked and then DISCHARGED — the resolved node keeps the values in layout order. *)
  and infer_init sn (sl : Types.struct_layout) (args : Ast.arg list) span : Tast.expr =
    let fields = sl.Types.sl_fields in
    let values =
      if List.length args <> List.length fields then (
        err span
          (Printf.sprintf "'%s' initializer expects %d argument(s) but %d given" sn
             (List.length fields) (List.length args));
        List.map (fun (_, value) -> infer value) args)
      else
        List.map2
          (fun (label, value) (fname, ftype) ->
            (match label with
            | Some l when l <> fname ->
                err (Ast.expr_span value)
                  (Printf.sprintf "incorrect argument label in call (have '%s:', expected '%s:')"
                     l fname)
            | None ->
                err (Ast.expr_span value)
                  (Printf.sprintf "missing argument label '%s:' in call" fname)
            | _ -> ());
            check_expr value ftype)
          args fields
    in
    mk (Tast.Struct_init (sn, values)) (Types.TStruct sn) span
  and check_expr (e : Ast.expr) (expected : Types.ty) : Tast.expr =
    match e with
    | Ast.Int_lit (n, span) ->
        (* the coercion, RECORDED: the node keeps its kind and takes the expected type *)
        if expected = Types.TInt || expected = Types.TDouble then mk (Tast.Int_lit n) expected span
        else (
          err span
            (Printf.sprintf "cannot convert value of type 'Int' to specified type '%s'"
               (Types.string_of_ty expected));
          mk (Tast.Int_lit n) Types.TInt span)
    | Ast.Binary (((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div) as op), l, r, span)
      when Types.is_numeric expected ->
        mk (Tast.Binary (op, check_expr l expected, check_expr r expected)) expected span
    | Ast.Binary (Ast.Mod, l, r, span) when expected = Types.TInt ->
        mk (Tast.Binary (Ast.Mod, check_expr l Types.TInt, check_expr r Types.TInt)) Types.TInt span
    | Ast.Unary (Ast.Neg, e0, span) when Types.is_numeric expected ->
        mk (Tast.Unary (Ast.Neg, check_expr e0 expected)) expected span
    | _ ->
        let n = infer e in
        if not (Types.equal n.Tast.ty expected) then
          err (Ast.expr_span e)
            (Printf.sprintf "cannot convert value of type '%s' to specified type '%s'"
               (Types.string_of_ty n.Tast.ty) (Types.string_of_ty expected));
        n
  in
  (* does a block definitely return on every path? (the "missing return" check) *)
  let rec stmt_returns = function
    | Ast.Return _ -> true
    | Ast.If { then_blk; else_blk = Some e; _ } -> block_returns then_blk && block_returns e
    | _ -> false
  and block_returns stmts = List.exists stmt_returns stmts (* the rest is unreachable *) in
  let rec check_stmt (s : Ast.stmt) : Tast.stmt =
    match s with
    | Ast.Let { name; is_var; annot; value; span } ->
        let n =
          match annot with
          | None -> infer value
          | Some tyname -> (
              match resolve_opt tyname with
              | Some t -> check_expr value t
              | None ->
                  err span (Printf.sprintf "cannot find type '%s' in scope" tyname);
                  infer value)
        in
        bind name (n.Tast.ty, is_var);
        Tast.Let { name; is_var; value = n; span }
    | Ast.Assign { name; value; span } -> (
        match lookup name with
        | None ->
            err span (Printf.sprintf "cannot find '%s' in scope" name);
            Tast.Assign { name; value = infer value; span }
        | Some (t, is_var) ->
            if not is_var then
              err span (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant" name);
            Tast.Assign { name; value = check_expr value t; span })
    | Ast.Set_member { obj; field; value; span } -> (
        let unresolved t =
          err span (Printf.sprintf "value of type '%s' has no member '%s'" t field);
          Tast.Set_member { obj; field = 0; field_name = field; value = infer value; span }
        in
        match lookup obj with
        | None ->
            err span (Printf.sprintf "cannot find '%s' in scope" obj);
            Tast.Set_member { obj; field = 0; field_name = field; value = infer value; span }
        | Some (Types.TStruct sn, is_var) -> (
            let sl = Hashtbl.find_opt structs sn in
            match
              ( Option.bind sl (fun l -> Types.field_type l field),
                Option.bind sl (fun l -> Types.field_index l field) )
            with
            | Some ft, Some i ->
                (* swiftc's `diag::assignment_lhs_is_immutable_property`: the binding first, then
                   the field — a `let` field is immutable through every binding *)
                if not is_var then
                  err span
                    (Printf.sprintf "cannot assign to property: '%s' is a 'let' constant" obj)
                else if Hashtbl.mem let_fields (sn, field) then
                  err span
                    (Printf.sprintf "cannot assign to property: '%s' is a 'let' constant" field);
                Tast.Set_member
                  { obj; field = i; field_name = field; value = check_expr value ft; span }
            | _ -> unresolved sn)
        | Some (t, _) -> unresolved (Types.string_of_ty t))
    | Ast.Expr_stmt (e, _) -> Tast.Expr_stmt (infer e)
    | Ast.If { cond; then_blk; else_blk; span } ->
        let cond = check_expr cond Types.TBool in
        let then_blk = check_block then_blk in
        let else_blk = Option.map check_block else_blk in
        Tast.If { cond; then_blk; else_blk; span }
    | Ast.While { cond; body; span } ->
        let cond = check_expr cond Types.TBool in
        incr loop_depth;
        let body = check_block body in
        decr loop_depth;
        Tast.While { cond; body; span }
    | Ast.For { var; lo; hi; body; span } ->
        let lo = check_expr lo Types.TInt in
        let hi = check_expr hi Types.TInt in
        incr loop_depth;
        let body' = ref [] in
        in_scope (fun () ->
            bind var (Types.TInt, false);
            body' := List.map check_stmt body);
        decr loop_depth;
        Tast.For { var; lo; hi; body = !body'; span }
    | Ast.Break span ->
        if !loop_depth = 0 then err span "'break' is only allowed inside a loop";
        Tast.Break span
    | Ast.Continue span ->
        if !loop_depth = 0 then err span "'continue' is only allowed inside a loop";
        Tast.Continue span
    | Ast.Return (eo, span) -> (
        match !current_ret with
        | None ->
            err span "return invalid outside of a func";
            Tast.Return (None, span)
        | Some rt -> (
            match eo with
            | Some e ->
                if rt = Types.TVoid then (
                  err span "unexpected non-void return value in void function";
                  Tast.Return (None, span))
                else Tast.Return (Some (check_expr e rt), span)
            | None ->
                if rt <> Types.TVoid then err span "non-void function should return a value";
                Tast.Return (None, span)))
  and check_block (stmts : Ast.stmt list) : Tast.stmt list =
    let out = ref [] in
    in_scope (fun () -> out := List.map check_stmt stmts);
    !out
  in

  let check_func (f : Ast.func_decl) : Tast.func_decl =
    let ret = match f.Ast.ret with None -> Types.TVoid | Some n -> resolve_ty f.Ast.fspan n in
    let saved_env = !env and saved_ret = !current_ret in
    env := [];
    current_ret := Some ret;
    let params =
      List.map
        (fun (pr : Ast.param) ->
          let pty = resolve_ty f.Ast.fspan pr.Ast.ptype in
          bind pr.Ast.pname (pty, false);
          { Tast.pname = pr.Ast.pname; pty })
        f.Ast.params
    in
    let body = List.map check_stmt f.Ast.body in
    env := saved_env;
    current_ret := saved_ret;
    if ret <> Types.TVoid && not (block_returns f.Ast.body) then
      err f.Ast.fspan
        (Printf.sprintf "missing return in %s expected to return '%s'" "global function"
           (Types.string_of_ty ret));
    { Tast.fname = f.Ast.fname; params; ret; body; fspan = f.Ast.fspan }
  in

  (* PASS 0: register struct and enum names (so declarations can reference each other), then
     fill the layouts. Now any type name resolves and the registries are known to passes 1–2. *)
  List.iter
    (function
      | Ast.IStruct s ->
          if Hashtbl.mem structs s.Ast.sname || Hashtbl.mem enums s.Ast.sname then
            err s.Ast.sspan (Printf.sprintf "invalid redeclaration of '%s'" s.Ast.sname);
          Hashtbl.replace structs s.Ast.sname { Types.sl_name = s.Ast.sname; sl_fields = [] }
      | Ast.IEnum e ->
          (* TODO(11d): predeclare the enum NAME so later layouts may refer to it. Structs and
             enums share one type namespace, so a clash with either is a redeclaration. *)
          ignore e;
          failwith "TODO(11d): register an enum name"
      | _ -> ())
    prog.Ast.items;
  List.iter
    (function
      | Ast.IStruct s ->
          let fields =
            List.map (fun (fl : Ast.field) -> (fl.Ast.fld_name, resolve_ty s.Ast.sspan fl.Ast.fld_ty)) s.Ast.sfields
          in
          List.iter
            (fun (fl : Ast.field) -> if not fl.Ast.fld_var then Hashtbl.replace let_fields (s.Ast.sname, fl.Ast.fld_name) ())
            s.Ast.sfields;
          Hashtbl.replace structs s.Ast.sname { Types.sl_name = s.Ast.sname; sl_fields = fields }
      | Ast.IEnum e ->
          ignore e;
          (* TODO(11d): resolve every associated-value type, enforce this concept's Int-only
             payload/raw-type boundary, and replace the placeholder registered above with the
             completed layout. §2. *)
          failwith "TODO(11d): complete an enum layout"
      | _ -> ())
    prog.Ast.items;
  (* PASS 1: collect signatures so calls/recursion/forward-references resolve. *)
  List.iter
    (function
      | Ast.IFunc f ->
          if Hashtbl.mem funcs f.Ast.fname then
            err f.Ast.fspan (Printf.sprintf "invalid redeclaration of '%s'" f.Ast.fname);
          let ptypes = List.map (fun (pr : Ast.param) -> resolve_silent pr.Ast.ptype) f.Ast.params in
          let ret = match f.Ast.ret with None -> Types.TVoid | Some n -> resolve_silent n in
          Hashtbl.replace funcs f.Ast.fname (ptypes, ret)
      | _ -> ())
    prog.Ast.items;
  (* PASS 2: check bodies and top-level statements, in order — producing the typed program. The
     struct and enum LAYOUTS travel with it, so SILGen lowers what the checker checked. *)
  let items =
    List.map
      (function
        | Ast.IFunc f -> Tast.IFunc (check_func f)
        | Ast.IStmt s -> Tast.IStmt (check_stmt s)
        | Ast.IStruct sd -> Tast.IStruct (Hashtbl.find structs sd.Ast.sname)
        | Ast.IEnum ed -> Tast.IEnum (Hashtbl.find enums ed.Ast.ename))
      prog.Ast.items
  in
  if Diagnostics.has_errors diags then None else Some { Tast.items }
