(* Sema — concept 06 (skeleton): concept-05 bidirectional checking + control flow.

   Concept 05 is filled in for you. Fill the TODO(06) holes:
     - logical && / || : both operands Bool, result Bool
     - if / while conditions must be Bool; for v in lo ..< hi : lo, hi are Int and v is an
       immutable Int in the body's scope; break / continue only inside a loop.
   The scope helpers (bind/lookup/in_scope/check_block) and loop_depth are given.

   Reference: solution/sema.ml. *)

let check (program : Ast.program) (diagnostics : Diagnostics.sink) : unit =
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

  let rec is_int_literal = function
    | Ast.Int_lit _ -> true
    | Ast.Unary (Ast.Neg, expression, _) -> is_int_literal expression
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
  let rec infer (expression : Ast.expr) : Types.ty =
    match expression with
    | Ast.Int_lit _ -> Types.TInt
    | Ast.Double_lit _ -> Types.TDouble
    | Ast.Bool_lit _ -> Types.TBool
    | Ast.String_lit _ -> Types.TString
    | Ast.Var (x, span) -> (
        match lookup x with
        | Some (t, _) -> t
        | None ->
            report_error span (Printf.sprintf "cannot find '%s' in scope" x);
            Types.TInt)
    | Ast.Unary (Ast.Neg, e0, span) ->
        let t = infer e0 in
        if Types.is_numeric t then t
        else (
          report_error span
            (Printf.sprintf "unary operator '-' cannot be applied to an operand of type '%s'"
               (Types.string_of_ty t));
          t)
    | Ast.Binary (op, l, r, span) -> infer_binary op l r span
    | Ast.Call (f, args, span) -> infer_call f args span
    (* `expression as T`: the type is written, so there is nothing to synthesise — CHECK the
       operand against it. The one arm where `infer` calls `check_expr`. *)
    | Ast.Ascribe (e0, tyname, span) -> (
        match Types.of_name tyname with
        | Some t ->
            check_expr e0 t;
            t
        | None ->
            report_error span (Printf.sprintf "cannot find type '%s' in scope" tyname);
            infer e0)
  and infer_binary op l r span : Types.ty =
    let tl = infer l and tr = infer r in
    let bad () =
      (* swiftc has two wordings and picks by whether the operands agree:
           1 < "a"      -> cannot be applied to operands of type 'Int' and 'String'
           true < false -> cannot be applied to two 'Bool' operands *)
      report_error span
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
        ignore bad;
        (* TODO(06): both operands must be Bool; result is Bool (else report via bad ()). *)
        failwith "TODO(06): type && / ||"
  and infer_call f args span : Types.ty =
    if f = "print" then (
      (match args with
      | [ a ] -> ignore (infer a)
      | _ ->
          report_error span "print(_:) expects exactly one argument";
          List.iter (fun a -> ignore (infer a)) args);
      Types.TInt)
    else (
      report_error span (Printf.sprintf "cannot find '%s' in scope" f);
      List.iter (fun a -> ignore (infer a)) args;
      Types.TInt)
  and check_expr (expression : Ast.expr) (expected : Types.ty) : unit =
    match expression with
    | Ast.Int_lit _ ->
        if expected = Types.TInt || expected = Types.TDouble then ()
        else
          report_error (Ast.expr_span expression)
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
        let t = infer expression in
        if not (Types.equal t expected) then
          report_error (Ast.expr_span expression)
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
                  report_error span (Printf.sprintf "cannot find type '%s' in scope" tyname);
                  infer value)
        in
        bind name (t, is_var)
    | Ast.Assign { name; value; span } -> (
        match lookup name with
        | None ->
            report_error span (Printf.sprintf "cannot find '%s' in scope" name);
            ignore (infer value)
        | Some (t, is_var) ->
            if not is_var then
              report_error span (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant" name);
            check_expr value t)
    | Ast.Expr_stmt (expression, _) -> ignore (infer expression)
    | Ast.If _ | Ast.While _ | Ast.For _ | Ast.Break _ | Ast.Continue _ ->
        ignore loop_depth;
        ignore check_block;
        (* TODO(06): the control-flow rules — conditions are Bool; `for` binds an IMMUTABLE Int over
           an Int range in a fresh scope; `break`/`continue` need an enclosing loop (loop_depth).
           The tests pin swiftc's wording for each rejection. §3. *)
        failwith "TODO(06): check control-flow statements"
  and check_block (statements : Ast.stmt list) : unit = in_scope (fun () -> List.iter check_stmt statements) in
  List.iter check_stmt program.Ast.stmts
