(* Sema — concept 08 (GIVEN, complete): concepts 05-07: concepts 05–06 + functions.

   New vs 06:
     - a function-signature table built in a FIRST PASS (so calls, recursion, and forward
       references all resolve), then bodies checked in a second pass
     - call checking: arity + each argument against its parameter type; result = return type
     - return statements checked against the enclosing function's return type
     - the "missing return" check (a non-Void function must definitely return on every path)
     - functions are self-contained (params + the function table only — no top-level capture)
     - print and Void functions yield () (Types.TVoid)

   As in 05, the checker PRODUCES a `Tast.program` rather than returning a verdict. Functions
   make that concrete: a `Tast.func_decl` carries RESOLVED parameter and return types, so the
   written type names never travel past this file. And `Ast.Call` — which could be print, a
   declared function, or an unknown name — becomes whichever it actually was. PLAN.md §0.1. *)

(* Does a block definitely return on every path? — the "missing return" analysis. Pure functions
   of the AST, so they live at module level and can be tested on their own. *)
let rec stmt_returns = function
  | Ast.Return _ -> true
  | Ast.If { then_blk; else_blk = Some expression; _ } ->
      block_returns then_blk && block_returns expression
  | _ -> false

and block_returns statements =
  List.exists stmt_returns statements (* the rest is unreachable *)

let check (program : Ast.program) (diagnostics : Diagnostics.sink) : Tast.program option =
  (* a scope stack: innermost binding first, so List.assoc_opt finds the closest one *)
  let environment : (string * (Types.ty * bool)) list ref = ref [] in
  let loop_depth = ref 0 in
  (* `current_return_type` — None means "not inside a function"; Some t means "inside one, and it
     returns t". `functions` — every signature, filled by pass 1 and read by pass 2, which is
     what lets a call resolve whether the callee is declared above it or below. *)
  let current_return_type : Types.ty option ref = ref None in
  let functions : (string, Types.ty list * Types.ty) Hashtbl.t = Hashtbl.create 16 in
  let report_error span msg = Diagnostics.error diagnostics span msg in
  let lookup x = List.assoc_opt x !environment in
  let bind name v = environment := (name, v) :: !environment in
  let in_scope (f : unit -> unit) =
    let saved = !environment in
    f ();
    environment := saved
  in
  let resolve_silent name = Option.value (Types.of_name name) ~default:Types.TInt in
  let resolve_ty span name =
    match Types.of_name name with
    | Some t -> t
    | None ->
        report_error span (Printf.sprintf "cannot find type '%s' in scope" name);
        Types.TInt
  in
  let mk (e : Tast.expr_kind) (ty : Types.ty) (span : Token.span) : Tast.expr = { Tast.e; ty; span } in

  (* `%` is absent: Swift has no `%` on Double, so a tree containing one can never take it *)
  let rec is_int_literal = function
    | Ast.Int_lit _ -> true
    | Ast.Unary (Ast.Neg, expression, _) -> is_int_literal expression
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
  let rec infer (expression : Ast.expr) : Tast.expr =
    match expression with
    | Ast.Int_lit (n, span) -> mk (Tast.Int_lit n) Types.TInt span
    | Ast.Double_lit (f, span) -> mk (Tast.Double_lit f) Types.TDouble span
    | Ast.Bool_lit (b, span) -> mk (Tast.Bool_lit b) Types.TBool span
    | Ast.String_lit (s, span) -> mk (Tast.String_lit s) Types.TString span
    | Ast.Var (x, span) -> (
        (* RESOLUTION: a name becomes a binding, or it is an error. Nothing downstream re-asks. *)
        match lookup x with
        | Some (t, _) -> mk (Tast.Local x) t span
        | None ->
            report_error span (Printf.sprintf "cannot find '%s' in scope" x);
            mk (Tast.Local x) Types.TInt span)
    | Ast.Unary (Ast.Neg, e0, span) ->
        let n = infer e0 in
        if not (Types.is_numeric n.Tast.ty) then
          report_error span
            (Printf.sprintf "unary operator '-' cannot be applied to an operand of type '%s'"
               (Types.string_of_ty n.Tast.ty));
        mk (Tast.Unary (Ast.Neg, n)) n.Tast.ty span
    | Ast.Binary (op, l, r, span) -> infer_binary op l r span
    | Ast.Call (f, args, span) -> infer_call f args span
    (* `expression as T`: the type is written, so there is nothing to synthesise — CHECK the
       operand against it. The one arm where `infer` calls `check_expr`. *)
    | Ast.Ascribe (e0, tyname, span) -> (
        match Types.of_name tyname with
        | Some t -> mk (Tast.Coerce (check_expr e0 t)) t span
        | None ->
            report_error span (Printf.sprintf "cannot find type '%s' in scope" tyname);
            let n = infer e0 in
            mk (Tast.Coerce n) n.Tast.ty span)
  and infer_binary op l r span : Tast.expr =
    let ln = infer l and rn = infer r in
    let tl = ln.Tast.ty and tr = rn.Tast.ty in
    let bad () =
      (* swiftc has two wordings and picks by whether the operands agree:
           1 < "a"      -> cannot be applied to operands of type 'Int' and 'String'
           true < false -> cannot be applied to two 'Bool' operands *)
      report_error span
        (if tl = tr then
           Printf.sprintf "binary operator '%s' cannot be applied to two '%s' operands"
             (Ast.string_of_binop op) (Types.string_of_ty tl)
         else
           Printf.sprintf
             "binary operator '%s' cannot be applied to operands of type '%s' and '%s'"
             (Ast.string_of_binop op) (Types.string_of_ty tl) (Types.string_of_ty tr));
      Types.TInt
    in
    let unified = unify l tl r tr in
    (* APPLY the solution: a side that flexed is re-checked AT the unified type, so its literal
       nodes come back carrying it. swiftc's CSApply, in miniature. *)
    let ln, rn =
      match unified with
      | Some t ->
          ( (if Types.equal tl t then ln else check_expr l t),
            if Types.equal tr t then rn else check_expr r t )
      | None -> (ln, rn)
    in
    let result =
      match op with
      | Ast.Add -> (
          match unified with
          | Some ((Types.TInt | Types.TDouble) as t) -> t
          | Some Types.TString -> Types.TString
          | _ -> bad ())
      | Ast.Sub | Ast.Mul | Ast.Div -> (
          match unified with Some ((Types.TInt | Types.TDouble) as t) -> t | _ -> bad ())
      | Ast.Mod -> ( match unified with Some Types.TInt -> Types.TInt | _ -> bad ())
      | Ast.Eq | Ast.Ne -> (
          match unified with
          | Some _ -> Types.TBool
          | None ->
              ignore (bad ());
              Types.TBool)
      | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge -> (
          match unified with
          | Some (Types.TInt | Types.TDouble | Types.TString) -> Types.TBool
          | _ ->
              ignore (bad ());
              Types.TBool)
      | Ast.And | Ast.Or ->
          if tl = Types.TBool && tr = Types.TBool then Types.TBool
          else (
            ignore (bad ());
            Types.TBool)
    in
    mk (Tast.Binary (op, ln, rn)) result span
  and infer_call f args span : Tast.expr =
    (* RESOLUTION. `Ast.Call (f, args)` is three different things depending on `f`; deciding
       which is this function's job, and the node records the answer. *)
    let some_arg ns = match ns with n :: _ -> n | [] -> mk (Tast.Int_lit 0) Types.TInt span in
    match Hashtbl.find_opt functions f with
    | Some (ptypes, ret) ->
        let np = List.length ptypes and na = List.length args in
        if np <> na then (
          report_error span
            (Printf.sprintf "function '%s' expects %d argument(s) but %d given" f np na);
          mk (Tast.Fn_call (f, List.map infer args)) ret span)
        else mk (Tast.Fn_call (f, List.map2 check_expr args ptypes)) ret span
    | None ->
        if f = "print" then
          match args with
          | [ a ] -> mk (Tast.Print (infer a)) Types.TVoid span
          | _ ->
              report_error span "print(_:) expects exactly one argument";
              mk (Tast.Print (some_arg (List.map infer args))) Types.TVoid span
        else (
          report_error span (Printf.sprintf "cannot find '%s' in scope" f);
          mk (Tast.Print (some_arg (List.map infer args))) Types.TInt span)
  and check_expr (expression : Ast.expr) (expected : Types.ty) : Tast.expr =
    match expression with
    | Ast.Int_lit (n, span) ->
        (* the coercion, RECORDED: the node keeps its kind and takes the expected type, exactly
           as `swiftc -dump-ast` shows (`integer_literal_expr type="Double"`) *)
        if expected = Types.TInt || expected = Types.TDouble then mk (Tast.Int_lit n) expected span
        else (
          report_error span
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
        let n = infer expression in
        if not (Types.equal n.Tast.ty expected) then
          report_error (Ast.expr_span expression)
            (Printf.sprintf "cannot convert value of type '%s' to specified type '%s'"
               (Types.string_of_ty n.Tast.ty) (Types.string_of_ty expected));
        n
  in
  let rec check_stmt (s : Ast.stmt) : Tast.stmt =
    match s with
    | Ast.Let { name; is_var; annot; value; span } ->
        let n =
          match annot with
          | None -> infer value
          | Some tyname -> (
              match Types.of_name tyname with
              | Some t -> check_expr value t
              | None ->
                  report_error span (Printf.sprintf "cannot find type '%s' in scope" tyname);
                  infer value)
        in
        bind name (n.Tast.ty, is_var);
        Tast.Let { name; is_var; value = n; span }
    | Ast.Assign { name; value; span } -> (
        match lookup name with
        | None ->
            report_error span (Printf.sprintf "cannot find '%s' in scope" name);
            Tast.Assign { name; value = infer value; span }
        | Some (t, is_var) ->
            if not is_var then
              report_error span
                (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant" name);
            Tast.Assign { name; value = check_expr value t; span })
    | Ast.Expr_stmt (expression, _) -> Tast.Expr_stmt (infer expression)
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
            (* the loop variable is an immutable Int, in scope only in the body *)
            bind var (Types.TInt, false);
            body' := List.map check_stmt body);
        decr loop_depth;
        Tast.For { var; lo; hi; body = !body'; span }
    | Ast.Break span ->
        if !loop_depth = 0 then report_error span "'break' is only allowed inside a loop";
        Tast.Break span
    | Ast.Continue span ->
        if !loop_depth = 0 then report_error span "'continue' is only allowed inside a loop";
        Tast.Continue span
    | Ast.Return (eo, span) -> (
        match !current_return_type with
        | None ->
            report_error span "return invalid outside of a func";
            Tast.Return (None, span)
        | Some rt -> (
            match eo with
            | Some expression ->
                if rt = Types.TVoid then (
                  report_error span "unexpected non-void return value in void function";
                  Tast.Return (None, span))
                else Tast.Return (Some (check_expr expression rt), span)
            | None ->
                if rt <> Types.TVoid then report_error span "non-void function should return a value";
                Tast.Return (None, span)))
  and check_block (statements : Ast.stmt list) : Tast.stmt list =
    let out = ref [] in
    in_scope (fun () -> out := List.map check_stmt statements);
    !out
  in
  (* check one function body: a fresh scope with the parameters; then "missing return" *)
  let check_func (f : Ast.func_decl) : Tast.func_decl =
    let ret = match f.Ast.ret with None -> Types.TVoid | Some n -> resolve_ty f.Ast.fspan n in
    let saved_env = !environment and saved_ret = !current_return_type in
    environment := [];
    current_return_type := Some ret;
    let params =
      List.map
        (fun (pr : Ast.param) ->
          let pty = resolve_ty f.Ast.fspan pr.Ast.ptype in
          bind pr.Ast.pname (pty, false);
          { Tast.pname = pr.Ast.pname; pty })
        f.Ast.params
    in
    let body = List.map check_stmt f.Ast.body in
    environment := saved_env;
    current_return_type := saved_ret;
    if ret <> Types.TVoid && not (block_returns f.Ast.body) then
      report_error f.Ast.fspan
        (Printf.sprintf "missing return in global function expected to return '%s'"
           (Types.string_of_ty ret));
    { Tast.fname = f.Ast.fname; params; ret; body; fspan = f.Ast.fspan }
  in

  (* PASS 1: collect signatures so calls/recursion/forward-references resolve. *)
  List.iter
    (function
      | Ast.IFunc f ->
          if Hashtbl.mem functions f.Ast.fname then
            report_error f.Ast.fspan
              (Printf.sprintf "invalid redeclaration of '%s'" f.Ast.fname);
          let ptypes = List.map (fun (pr : Ast.param) -> resolve_silent pr.Ast.ptype) f.Ast.params in
          let ret = match f.Ast.ret with None -> Types.TVoid | Some n -> resolve_silent n in
          Hashtbl.replace functions f.Ast.fname (ptypes, ret)
      | Ast.IStmt _ -> ())
    program.Ast.items;
  (* PASS 2: check bodies and top-level statements, in order — producing the typed program. *)
  let items =
    List.map
      (function
        | Ast.IFunc f -> Tast.IFunc (check_func f)
        | Ast.IStmt s -> Tast.IStmt (check_stmt s))
      program.Ast.items
  in
  if Diagnostics.has_errors diagnostics then None else Some { Tast.items }
