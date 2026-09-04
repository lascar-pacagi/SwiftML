(* FROZEN SOLUTION — concept 12 sema (+ switch/exhaustiveness): concepts 05–06 + functions.

   New vs 06:
     - a function-signature table built in a FIRST PASS (so calls, recursion, and forward
       references all resolve), then bodies checked in a second pass
     - call checking: arity + each argument against its parameter type; result = return type
     - return statements checked against the enclosing function's return type
     - the "missing return" check (a non-Void function must definitely return on every path)
     - functions are self-contained (params + the function table only — no top-level capture)
     - print and Void functions yield () (Types.TVoid) *)

let check (prog : Ast.program) (diags : Diagnostics.sink) : unit =
  let env : (string * (Types.ty * bool)) list ref = ref [] in
  let loop_depth = ref 0 in
  let current_ret : Types.ty option ref = ref None in
  let funcs : (string, Types.ty list * Types.ty) Hashtbl.t = Hashtbl.create 16 in
  let structs : (string, Types.struct_layout) Hashtbl.t = Hashtbl.create 16 in
  let enums : (string, Types.enum_layout) Hashtbl.t = Hashtbl.create 16 in
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

  let rec is_int_literal = function
    | Ast.Int_lit _ -> true
    | Ast.Unary (Ast.Neg, e, _) -> is_int_literal e
    | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div | Ast.Mod), a, b, _) ->
        is_int_literal a && is_int_literal b
    | _ -> false
  in
  let unify l tl r tr : Types.ty option =
    if Types.equal tl tr then Some tl
    else if is_int_literal l && tr = Types.TDouble then Some Types.TDouble
    else if is_int_literal r && tl = Types.TDouble then Some Types.TDouble
    else None
  in
  let rec infer (e : Ast.expr) : Types.ty =
    match e with
    | Ast.Int_lit _ -> Types.TInt
    | Ast.Double_lit _ -> Types.TDouble
    | Ast.Bool_lit _ -> Types.TBool
    | Ast.String_lit _ -> Types.TString
    | Ast.Var (x, span) -> (
        match lookup x with
        | Some (t, _) -> t
        | None ->
            err span (Printf.sprintf "cannot find '%s' in scope" x);
            Types.TInt)
    | Ast.Unary (Ast.Neg, e0, span) ->
        let t = infer e0 in
        if Types.is_numeric t then t
        else (
          err span
            (Printf.sprintf "unary operator '-' cannot be applied to an operand of type '%s'"
               (Types.string_of_ty t));
          t)
    | Ast.Binary (op, l, r, span) -> infer_binary op l r span
    | Ast.Call (f, args, span) -> infer_call f args span
    (* `e as T`: the type is written, so there is nothing to synthesise — CHECK the
       operand against it. The one arm where `infer` calls `check_expr`. *)
    | Ast.Ascribe (e0, tyname, span) -> (
        match Types.of_name tyname with
        | Some t ->
            check_expr e0 t;
            t
        | None ->
            err span (Printf.sprintf "cannot find type '%s' in scope" tyname);
            infer e0)
    (* `E.case` — a no-payload enum case names a value of the enum type (concept 11) *)
    | Ast.Member (Ast.Var (tn, _), case, span) when Hashtbl.mem enums tn -> (
        let el = Hashtbl.find enums tn in
        match Types.case_payload el case with
        | Some [] -> Types.TEnum tn
        | Some _ ->
            err span (Printf.sprintf "enum case '%s.%s' requires arguments" tn case);
            Types.TEnum tn
        | None -> err span (Printf.sprintf "type '%s' has no case '%s'" tn case); Types.TEnum tn)
    | Ast.Member (e0, fld, span) -> (
        match infer e0 with
        | Types.TStruct sn -> (
            match Hashtbl.find_opt structs sn with
            | Some sl -> (
                match Types.field_type sl fld with
                | Some ft -> ft
                | None ->
                    err span (Printf.sprintf "value of type '%s' has no member '%s'" sn fld);
                    Types.TInt)
            | None -> Types.TInt)
        (* `e.rawValue` on a raw-value enum yields its Int raw value (concept 11) *)
        | Types.TEnum en when fld = "rawValue" && (Hashtbl.find enums en).Types.el_raw -> Types.TInt
        | t ->
            err span (Printf.sprintf "value of type '%s' has no member '%s'" (Types.string_of_ty t) fld);
            Types.TInt)
    (* `E.case(args)` — a payload-carrying enum case (concept 11) *)
    | Ast.Method_call (Ast.Var (tn, _), case, args, span) when Hashtbl.mem enums tn -> (
        let el = Hashtbl.find enums tn in
        match Types.case_payload el case with
        | Some tys ->
            let exprs = List.map snd args in
            if List.length tys <> List.length exprs then
              err span
                (Printf.sprintf "enum case '%s.%s' expects %d associated value(s) but %d given" tn case
                   (List.length tys) (List.length exprs))
            else List.iter2 (fun e t -> check_expr e t) exprs tys;
            Types.TEnum tn
        | None -> err span (Printf.sprintf "type '%s' has no case '%s'" tn case); Types.TEnum tn)
    | Ast.Method_call (e0, _, _, span) ->
        ignore (infer e0);
        err span "methods are not supported in this subset (Phase 3 v0)";
        Types.TInt
  and infer_binary op l r span : Types.ty =
    let tl = infer l and tr = infer r in
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
    match op with
    | Ast.Add -> (
        match unify l tl r tr with
        | Some ((Types.TInt | Types.TDouble) as t) -> t
        | Some Types.TString -> Types.TString
        | _ -> bad ())
    | Ast.Sub | Ast.Mul | Ast.Div -> (
        match unify l tl r tr with Some ((Types.TInt | Types.TDouble) as t) -> t | _ -> bad ())
    | Ast.Mod -> ( match unify l tl r tr with Some Types.TInt -> Types.TInt | _ -> bad ())
    | Ast.Eq | Ast.Ne -> (
        match unify l tl r tr with
        (* a payload-free enum is implicitly Equatable; an associated-value enum needs an explicit
           `: Equatable` conformance (deferred), so swiftc — and we — reject `==` on it *)
        | Some (Types.TEnum en) when Types.has_payload (Hashtbl.find enums en) ->
            err span (Printf.sprintf "type '%s' does not conform to protocol 'Equatable'" en);
            Types.TBool
        | Some _ -> Types.TBool
        | None -> ignore (bad ()); Types.TBool)
    | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge -> (
        match unify l tl r tr with
        | Some (Types.TInt | Types.TDouble | Types.TString) -> Types.TBool
        | _ -> ignore (bad ()); Types.TBool)
    | Ast.And | Ast.Or ->
        if tl = Types.TBool && tr = Types.TBool then Types.TBool else (ignore (bad ()); Types.TBool)
  and infer_call f args span : Types.ty =
    match Hashtbl.find_opt structs f with
    | Some sl -> infer_init f sl args span (* `Point(x: 1, y: 2)` — memberwise initializer *)
    | None -> (
        let exprs = List.map snd args in
        match Hashtbl.find_opt funcs f with
        | Some (ptypes, ret) ->
            let np = List.length ptypes and na = List.length exprs in
            if np <> na then
              err span (Printf.sprintf "function '%s' expects %d argument(s) but %d given" f np na)
            else List.iter2 (fun a t -> check_expr a t) exprs ptypes;
            ret
        | None ->
            if f = "print" then (
              (match exprs with
              | [ a ] -> ignore (infer a)
              | _ ->
                  err span "print(_:) expects exactly one argument";
                  List.iter (fun a -> ignore (infer a)) exprs);
              Types.TVoid)
            else (
              err span (Printf.sprintf "cannot find '%s' in scope" f);
              List.iter (fun a -> ignore (infer a)) exprs;
              Types.TInt))
  (* the memberwise initializer: one labeled argument per stored property, in order *)
  and infer_init sn (sl : Types.struct_layout) (args : Ast.arg list) span : Types.ty =
    let fields = sl.Types.sl_fields in
    if List.length args <> List.length fields then
      err span
        (Printf.sprintf "'%s' initializer expects %d argument(s) but %d given" sn (List.length fields)
           (List.length args))
    else
      List.iter2
        (fun (label, value) (fname, ftype) ->
          (match label with
          | Some l when l <> fname ->
              err (Ast.expr_span value)
                (Printf.sprintf "incorrect argument label in call (have '%s:', expected '%s:')" l fname)
          | None -> err (Ast.expr_span value) (Printf.sprintf "missing argument label '%s:' in call" fname)
          | _ -> ());
          check_expr value ftype)
        args fields;
    Types.TStruct sn
  and check_expr (e : Ast.expr) (expected : Types.ty) : unit =
    match e with
    | Ast.Int_lit _ ->
        if expected = Types.TInt || expected = Types.TDouble then ()
        else
          err (Ast.expr_span e)
            (Printf.sprintf "cannot convert value of type 'Int' to specified type '%s'"
               (Types.string_of_ty expected))
    | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div), l, r, _) when Types.is_numeric expected ->
        check_expr l expected;
        check_expr r expected
    | Ast.Binary (Ast.Mod, l, r, _) when expected = Types.TInt ->
        check_expr l Types.TInt;
        check_expr r Types.TInt
    | Ast.Unary (Ast.Neg, e0, _) when Types.is_numeric expected -> check_expr e0 expected
    | _ ->
        let t = infer e in
        if not (Types.equal t expected) then
          err (Ast.expr_span e)
            (Printf.sprintf "cannot convert value of type '%s' to specified type '%s'"
               (Types.string_of_ty t) (Types.string_of_ty expected))
  in
  (* does a block definitely return on every path? (the "missing return" check) *)
  let rec stmt_returns = function
    | Ast.Return _ -> true
    | Ast.If { then_blk; else_blk = Some e; _ } -> block_returns then_blk && block_returns e
    (* a switch definitely returns if every case body returns and (the default returns, or — when
       there's no default — the switch is exhaustive, which sema has already guaranteed) *)
    | Ast.Switch { cases; default; _ } ->
        List.for_all (fun (_, body) -> block_returns body) cases
        && (match default with Some d -> block_returns d | None -> true)
    | _ -> false
  and block_returns stmts = List.exists stmt_returns stmts (* the rest is unreachable *) in
  let rec check_stmt (s : Ast.stmt) : unit =
    match s with
    | Ast.Let { name; is_var; annot; value; span } ->
        let t =
          match annot with
          | None -> infer value
          | Some tyname -> (
              match resolve_opt tyname with
              | Some t -> check_expr value t; t
              | None -> err span (Printf.sprintf "cannot find type '%s' in scope" tyname); infer value)
        in
        bind name (t, is_var)
    | Ast.Assign { name; value; span } -> (
        match lookup name with
        | None -> err span (Printf.sprintf "cannot find '%s' in scope" name); ignore (infer value)
        | Some (t, is_var) ->
            if not is_var then
              err span (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant" name);
            check_expr value t)
    | Ast.Set_member { obj; field; value; span } -> (
        match lookup obj with
        | None -> err span (Printf.sprintf "cannot find '%s' in scope" obj); ignore (infer value)
        | Some (Types.TStruct sn, is_var) -> (
            match Option.bind (Hashtbl.find_opt structs sn) (fun sl -> Types.field_type sl field) with
            | Some ft ->
                if not is_var then
                  err span (Printf.sprintf "cannot assign to property '%s': '%s' is a 'let' constant" field obj);
                check_expr value ft
            | None ->
                err span (Printf.sprintf "value of type '%s' has no member '%s'" sn field);
                ignore (infer value))
        | Some (t, _) ->
            err span (Printf.sprintf "value of type '%s' has no member '%s'" (Types.string_of_ty t) field);
            ignore (infer value))
    | Ast.Expr_stmt (e, _) -> ignore (infer e)
    | Ast.If { cond; then_blk; else_blk; _ } ->
        check_expr cond Types.TBool;
        check_block then_blk;
        Option.iter check_block else_blk
    | Ast.While { cond; body; _ } ->
        check_expr cond Types.TBool;
        incr loop_depth; check_block body; decr loop_depth
    | Ast.For { var; lo; hi; body; _ } ->
        check_expr lo Types.TInt;
        check_expr hi Types.TInt;
        incr loop_depth;
        in_scope (fun () -> bind var (Types.TInt, false); List.iter check_stmt body);
        decr loop_depth
    | Ast.Switch { subject; cases; default; span } -> check_switch subject cases default span
    | Ast.Break span -> if !loop_depth = 0 then err span "'break' is only allowed inside a loop"
    | Ast.Continue span -> if !loop_depth = 0 then err span "'continue' is only allowed inside a loop"
    | Ast.Return (eo, span) -> (
        match !current_ret with
        | None -> err span "return invalid outside of a func"
        | Some rt -> (
            match eo with
            | Some e ->
                if rt = Types.TVoid then
                  err span "unexpected non-void return value in void function"
                else check_expr e rt
            | None ->
                if rt <> Types.TVoid then err span "non-void function should return a value"))
  (* type-check a `switch`: each pattern is checked against the subject; an enum-case pattern
     binds the case's associated values into the body scope; then EXHAUSTIVENESS (all enum cases
     covered, or a `default`). Mirrors swiftc's TypeCheckSwitchStmt. *)
  and check_switch subject cases default span : unit =
    match infer subject with
    | Types.TEnum en ->
        let el = Hashtbl.find enums en in
        let covered = ref [] in
        List.iter
          (fun (pat, body) ->
            match pat with
            | Ast.PEnumCase (cname, bindings) -> (
                match Types.case_payload el cname with
                | Some tys ->
                    covered := cname :: !covered;
                    let nb = List.length bindings and nt = List.length tys in
                    if nb <> nt then
                      err span
                        (Printf.sprintf "pattern '.%s' binds %d value(s) but case '%s' has %d associated value(s)"
                           cname nb cname nt);
                    in_scope (fun () ->
                        if nb = nt then
                          List.iter2
                            (fun b t -> match b with Ast.Bind x -> bind x (t, false) | Ast.Ignore -> ())
                            bindings tys;
                        List.iter check_stmt body)
                | None ->
                    err span (Printf.sprintf "type '%s' has no case '%s'" en cname);
                    check_block body)
            | Ast.PInt _ ->
                err span (Printf.sprintf "expression pattern of type 'Int' cannot match values of type '%s'" en);
                check_block body)
          cases;
        Option.iter check_block default;
        if default = None then begin
          let missing = List.filter (fun (c, _) -> not (List.mem c !covered)) el.Types.el_cases in
          if missing <> [] then err span "switch must be exhaustive"
        end
    | Types.TInt ->
        List.iter
          (fun (pat, body) ->
            (match pat with
            | Ast.PInt _ -> ()
            | Ast.PEnumCase (c, _) -> err span (Printf.sprintf "enum case '.%s' cannot match values of type 'Int'" c));
            check_block body)
          cases;
        Option.iter check_block default;
        if default = None then err span "switch must be exhaustive"
    | t -> err span (Printf.sprintf "cannot 'switch' over a value of type '%s'" (Types.string_of_ty t))
  and check_block (stmts : Ast.stmt list) : unit = in_scope (fun () -> List.iter check_stmt stmts) in

  (* check one function body: a fresh scope with the parameters; then "missing return" *)
  let check_func (f : Ast.func_decl) : unit =
    let ret = match f.Ast.ret with None -> Types.TVoid | Some n -> resolve_ty f.Ast.fspan n in
    let saved_env = !env and saved_ret = !current_ret in
    env := [];
    current_ret := Some ret;
    List.iter
      (fun (pr : Ast.param) -> bind pr.Ast.pname (resolve_ty f.Ast.fspan pr.Ast.ptype, false))
      f.Ast.params;
    List.iter check_stmt f.Ast.body;
    env := saved_env;
    current_ret := saved_ret;
    if ret <> Types.TVoid && not (block_returns f.Ast.body) then
      err f.Ast.fspan
        (Printf.sprintf "missing return in %s expected to return '%s'" "global function" (Types.string_of_ty ret))
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
          if Hashtbl.mem structs e.Ast.ename || Hashtbl.mem enums e.Ast.ename then
            err e.Ast.espan (Printf.sprintf "invalid redeclaration of '%s'" e.Ast.ename);
          Hashtbl.replace enums e.Ast.ename
            { Types.el_name = e.Ast.ename; el_cases = []; el_raw = e.Ast.eraw <> None }
      | _ -> ())
    prog.Ast.items;
  List.iter
    (function
      | Ast.IStruct s ->
          let fields =
            List.map (fun (fl : Ast.field) -> (fl.Ast.fld_name, resolve_ty s.Ast.sspan fl.Ast.fld_ty)) s.Ast.sfields
          in
          Hashtbl.replace structs s.Ast.sname { Types.sl_name = s.Ast.sname; sl_fields = fields }
      | Ast.IEnum e ->
          let cases =
            List.map
              (fun (c : Ast.enum_case) -> (c.Ast.cname, List.map (resolve_ty e.Ast.espan) c.Ast.payload))
              e.Ast.ecases
          in
          Hashtbl.replace enums e.Ast.ename
            { Types.el_name = e.Ast.ename; el_cases = cases; el_raw = e.Ast.eraw <> None }
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
  (* PASS 2: check bodies and top-level statements, in order. *)
  List.iter
    (function
      | Ast.IFunc f -> check_func f
      | Ast.IStmt s -> check_stmt s
      | Ast.IStruct _ | Ast.IEnum _ -> ())
    prog.Ast.items
