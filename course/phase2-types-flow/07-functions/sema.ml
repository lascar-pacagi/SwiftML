(* Sema — concept 07 (skeleton): concepts 05–06 + functions. Concepts 05–06 are filled in;
   you write the TODO(07) holes (call typing, return, check_func, the two passes). Reference:
   solution/sema.ml.

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
  let err span msg = Diagnostics.error diags span msg in
  let lookup x = List.assoc_opt x !env in
  let bind name v = env := (name, v) :: !env in
  let in_scope (f : unit -> unit) = let saved = !env in f (); env := saved in
  let resolve_silent name = Option.value (Types.of_name name) ~default:Types.TInt in
  let resolve_ty span name =
    match Types.of_name name with
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
            (Printf.sprintf "unary operator '-' cannot be applied to operand of type '%s'"
               (Types.string_of_ty t));
          t)
    | Ast.Binary (op, l, r, span) -> infer_binary op l r span
    | Ast.Call (f, args, span) -> infer_call f args span
  and infer_binary op l r span : Types.ty =
    let tl = infer l and tr = infer r in
    let bad () =
      err span
        (Printf.sprintf "binary operator '%s' cannot be applied to operands of type '%s' and '%s'"
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
        match unify l tl r tr with Some _ -> Types.TBool | None -> ignore (bad ()); Types.TBool)
    | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge -> (
        match unify l tl r tr with
        | Some (Types.TInt | Types.TDouble | Types.TString) -> Types.TBool
        | _ -> ignore (bad ()); Types.TBool)
    | Ast.And | Ast.Or ->
        if tl = Types.TBool && tr = Types.TBool then Types.TBool else (ignore (bad ()); Types.TBool)
  and infer_call f args span : Types.ty =
    match Hashtbl.find_opt funcs f with
    | Some (ptypes, ret) ->
        ignore ptypes;
        ignore ret;
        ignore span;
        (* TODO(07): call typing. Check arity ("function 'f' expects N argument(s) but M
           given") and, when it matches, each arg against its parameter type with check_expr;
           return the function's return type. *)
        failwith "TODO(07): type a function call"
    | None ->
        if f = "print" then (
          (match args with
          | [ a ] -> ignore (infer a)
          | _ ->
              err span "print(_:) expects exactly one argument";
              List.iter (fun a -> ignore (infer a)) args);
          Types.TVoid)
        else (
          err span (Printf.sprintf "cannot find '%s' in scope" f);
          List.iter (fun a -> ignore (infer a)) args;
          Types.TInt)
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
    | _ -> false
  and block_returns stmts =
    match List.rev stmts with last :: _ -> stmt_returns last | [] -> false
  in
  let rec check_stmt (s : Ast.stmt) : unit =
    match s with
    | Ast.Let { name; is_var; annot; value; span } ->
        let t =
          match annot with
          | None -> infer value
          | Some tyname -> (
              match Types.of_name tyname with
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
    | Ast.Break span -> if !loop_depth = 0 then err span "'break' is only allowed inside a loop"
    | Ast.Continue span -> if !loop_depth = 0 then err span "'continue' is only allowed inside a loop"
    | Ast.Return (eo, span) ->
        ignore eo;
        ignore span;
        ignore current_ret;
        (* TODO(07): `return` is valid only inside a function (check !current_ret, else
           "'return' invalid outside of a func"). With a value: Void function -> error
           "unexpected non-void return value in void function"; else check_expr against the
           return type. Without a value: non-Void -> "non-void function should return a value". *)
        failwith "TODO(07): check a return statement"
  and check_block (stmts : Ast.stmt list) : unit = in_scope (fun () -> List.iter check_stmt stmts) in

  (* check one function body: a fresh scope with the parameters; then "missing return" *)
  let check_func (f : Ast.func_decl) : unit =
    ignore f;
    ignore resolve_ty;
    ignore block_returns;
    (* TODO(07): resolve the return type; save/restore env + current_ret; set env := [] and
       current_ret := Some ret; bind each parameter immutable; check the body; then the
       "missing return" rule — a non-Void function whose body does not block_returns errors
       "missing return in function expected to return 'T'". *)
    failwith "TODO(07): check a function body"
  in

  ignore check_func;
  ignore resolve_silent;
  (* TODO(07): the two passes.
     PASS 1 — fill `funcs` with every function's signature (param types + return type), so
     calls, recursion, and forward references resolve. Report "invalid redeclaration of 'f'"
     on a duplicate name. Use resolve_silent for the types (PASS 1 doesn't diagnose).
     PASS 2 — walk the items in order: check_func each IFunc, check_stmt each IStmt. *)
  failwith "TODO(07): the two-pass driver"
