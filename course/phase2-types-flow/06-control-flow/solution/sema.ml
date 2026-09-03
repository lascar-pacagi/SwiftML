(* FROZEN SOLUTION — concept 06 sema: concept-05 bidirectional checking + control flow.

   New vs 05:
     - logical && / || : both operands Bool, result Bool
     - lexical block scopes: a binding made inside { … } is local to it (a scope stack)
     - if / while conditions must be Bool
     - for v in lo ..< hi : lo, hi must be Int; v is an immutable Int in the body's scope
     - break / continue are only valid inside a loop (tracked with a depth counter) *)

let check (prog : Ast.program) (diags : Diagnostics.sink) : unit =
  (* a scope stack: innermost binding first, so List.assoc_opt finds the closest one *)
  let env : (string * (Types.ty * bool)) list ref = ref [] in
  let loop_depth = ref 0 in
  let err span msg = Diagnostics.error diags span msg in
  let lookup x = List.assoc_opt x !env in
  let bind name v = env := (name, v) :: !env in
  let in_scope (f : unit -> unit) =
    let saved = !env in
    f ();
    env := saved
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
        | Some _ -> Types.TBool
        | None ->
            ignore (bad ());
            Types.TBool)
    | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge -> (
        match unify l tl r tr with
        | Some (Types.TInt | Types.TDouble | Types.TString) -> Types.TBool
        | _ ->
            ignore (bad ());
            Types.TBool)
    | Ast.And | Ast.Or ->
        if tl = Types.TBool && tr = Types.TBool then Types.TBool
        else (
          ignore (bad ());
          Types.TBool)
  and infer_call f args span : Types.ty =
    if f = "print" then (
      (match args with
      | [ a ] -> ignore (infer a)
      | _ ->
          err span "print(_:) expects exactly one argument";
          List.iter (fun a -> ignore (infer a)) args);
      Types.TInt)
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
  let rec check_stmt (s : Ast.stmt) : unit =
    match s with
    | Ast.Let { name; is_var; annot; value; span } ->
        let t =
          match annot with
          | None -> infer value
          | Some tyname -> (
              match Types.of_name tyname with
              | Some t ->
                  check_expr value t;
                  t
              | None ->
                  err span (Printf.sprintf "cannot find type '%s' in scope" tyname);
                  infer value)
        in
        bind name (t, is_var)
    | Ast.Assign { name; value; span } -> (
        match lookup name with
        | None ->
            err span (Printf.sprintf "cannot find '%s' in scope" name);
            ignore (infer value)
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
        incr loop_depth;
        check_block body;
        decr loop_depth
    | Ast.For { var; lo; hi; body; _ } ->
        check_expr lo Types.TInt;
        check_expr hi Types.TInt;
        incr loop_depth;
        in_scope (fun () ->
            bind var (Types.TInt, false);
            (* the loop variable is an immutable Int, in scope only in the body *)
            List.iter check_stmt body);
        decr loop_depth
    | Ast.Break span -> if !loop_depth = 0 then err span "'break' is only allowed inside a loop"
    | Ast.Continue span ->
        if !loop_depth = 0 then err span "'continue' is only allowed inside a loop"
  and check_block (stmts : Ast.stmt list) : unit = in_scope (fun () -> List.iter check_stmt stmts) in
  List.iter check_stmt prog.Ast.stmts
