(* FROZEN SOLUTION, WITH §6 EXERCISES 1, 2 and 3 APPLIED, — concept 06 sema: concept-05 bidirectional checking + control flow.

   New vs 05:
     - logical && / || : both operands Bool, result Bool
     - lexical block scopes: a binding made inside { … } is local to it (a scope stack)
     - if / while conditions must be Bool
     - for v in lo ..< hi : lo, hi must be Int; v is an immutable Int in the body's scope
     - break / continue are only valid inside a loop (tracked with a depth counter)

   As in 05, the checker PRODUCES a `Tast.program` rather than returning a verdict: every node
   carries its type and every resolved name is a node that can only mean that. PLAN.md §0.1. *)

let check (program : Ast.program) (diagnostics : Diagnostics.sink) : Tast.program option =
  (* a scope stack: innermost binding first, so List.assoc_opt finds the closest one *)
  let environment : (string * (Types.ty * bool)) list ref = ref [] in
  let loop_depth = ref 0 in
  let report_error span msg = Diagnostics.error diagnostics span msg in
  let lookup x = List.assoc_opt x !environment in
  let bind name v = environment := (name, v) :: !environment in
  let in_scope (f : unit -> unit) =
    let saved = !environment in
    f ();
    environment := saved
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
    (* the CHEAP test first: `is_int_literal` walks a whole subtree, and a Double-typed
       operand can never be an integer literal — asking anyway makes an accepted program
       like `1 + 1.5 + 1 + 1 + …` quadratic, since every level re-walks the spine below
       it. Same reason an error path hands back an error type rather than a plausible
       one: never re-ask a question whose answer is already settled. *)
    else if tr = Types.TDouble && is_int_literal l then Some Types.TDouble
    else if tl = Types.TDouble && is_int_literal r then Some Types.TDouble
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
    (* RESOLUTION: `print` is the only function this subset has *)
    let some_arg ns = match ns with n :: _ -> n | [] -> mk (Tast.Int_lit 0) Types.TInt span in
    if f = "print" then
      match args with
      | [ a ] -> mk (Tast.Print (infer a)) Types.TInt span
      | _ ->
          report_error span "print(_:) expects exactly one argument";
          mk (Tast.Print (some_arg (List.map infer args))) Types.TInt span
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
  (* Ast has no span accessor for statements, and one warning is not reason enough to
     widen the contract for every later concept. *)
  let stmt_span : Ast.stmt -> Token.span = function
    | Ast.Let { span; _ }
    | Ast.Assign { span; _ }
    | Ast.If { span; _ }
    | Ast.While { span; _ }
    | Ast.For { span; _ }
    | Ast.Repeat { span; _ } ->
        span
    | Ast.Expr_stmt (_, span) | Ast.Break span | Ast.Continue span -> span
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
    (* EX2: `closed` changes nothing here. Both operators take two Ints and bind an Int
       loop variable; the difference is one iteration at run time, which is concept 08's
       lowering to worry about, not the checker's. *)
    | Ast.For { var; lo; hi; closed = _; body; span } ->
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
    (* EX1: the body is checked INSIDE the loop context, exactly as `while`'s is — a
       `break` in there is legal. The condition is checked after it, and is not part of
       the loop for `break` purposes, which is why loop_depth is restored first. *)
    | Ast.Repeat { body; cond; span } ->
        incr loop_depth;
        let body = check_block body in
        decr loop_depth;
        let cond = check_expr cond Types.TBool in
        Tast.Repeat { body; cond; span }
  and check_block (statements : Ast.stmt list) : Tast.stmt list =
    warn_unreachable statements;
    let out = ref [] in
    in_scope (fun () -> out := List.map check_stmt statements);
    !out
  (* EX3: the concept's first FLOW-SENSITIVE check — it is not about any one statement's
     types, it is about the ORDER two statements appear in. A `break` or `continue` that
     is not the last statement of its block makes everything after it dead.

     Only a BARE break/continue counts. `if c { break }` may or may not leave the block,
     and deciding that needs the analysis Phase 4 builds properly — concept 17 deletes
     unreachable blocks once the CFG has made reachability a graph question. One pass
     down the list is the honest extent of a syntactic check. *)
  and warn_unreachable (statements : Ast.stmt list) : unit =
    let rec go = function
      | (Ast.Break _ as jump) :: (next :: _ as rest)
      | (Ast.Continue _ as jump) :: (next :: _ as rest) ->
          let word = match jump with Ast.Break _ -> "break" | _ -> "continue" in
          Diagnostics.warning diagnostics (stmt_span next)
            (Printf.sprintf "code after '%s' will never be executed" word);
          go rest
      | _ :: rest -> go rest
      | [] -> ()
    in
    go statements
  in
  let stmts = List.map check_stmt program.Ast.stmts in
  if Diagnostics.has_errors diagnostics then None else Some { Tast.stmts }
