(* FROZEN SOLUTION — concept 05 sema: the bidirectional type checker.

   Two modes, mutually recursive:
     infer e        -> ty        synthesize a type (no expectation)
     check_expr e t -> unit      check e against an expected type t (pushes t down)

   The one coercion is Swift's `ExpressibleByIntegerLiteral`: an *integer literal*
   (recursively, an arithmetic expression of integer literals) may take type Double when a
   Double is expected — so `let d: Double = 1 + 2` works, but `let d: Double = i` (i: Int)
   does not. Full literal flexibility is a constraint-solver job (Phase 5); we special-case
   the common shapes. *)

let check (prog : Ast.program) (diags : Diagnostics.sink) : unit =
  let env : (string, Types.ty * bool) Hashtbl.t = Hashtbl.create 16 in
  let err span msg = Diagnostics.error diags span msg in

  (* a "pure integer-literal" expression can flex to Double *)
  let rec is_int_literal = function
    | Ast.Int_lit _ -> true
    | Ast.Unary (Ast.Neg, e, _) -> is_int_literal e
    | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div | Ast.Mod), a, b, _) ->
        is_int_literal a && is_int_literal b
    | _ -> false
  in
  (* unify two operands' types, letting an integer literal become Double *)
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
        match Hashtbl.find_opt env x with
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
  and infer_call f args span : Types.ty =
    if f = "print" then (
      (match args with
      | [ a ] -> ignore (infer a)
      | _ ->
          err span "print(_:) expects exactly one argument";
          List.iter (fun a -> ignore (infer a)) args);
      Types.TInt (* print returns Void; placeholder, unused as a value *))
    else (
      err span (Printf.sprintf "cannot find '%s' in scope" f);
      List.iter (fun a -> ignore (infer a)) args;
      Types.TInt)
  and check_expr (e : Ast.expr) (expected : Types.ty) : unit =
    match e with
    | Ast.Int_lit _ ->
        (* integer literal: ExpressibleBy both Int and Double *)
        if expected = Types.TInt || expected = Types.TDouble then ()
        else
          err (Ast.expr_span e)
            (Printf.sprintf "cannot convert value of type 'Int' to specified type '%s'"
               (Types.string_of_ty expected))
    | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div), l, r, _) when Types.is_numeric expected ->
        (* push the expected numeric type into both operands: 1 + 2 checks as Double *)
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
  let check_stmt (s : Ast.stmt) : unit =
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
        Hashtbl.replace env name (t, is_var)
    | Ast.Assign { name; value; span } -> (
        match Hashtbl.find_opt env name with
        | None ->
            err span (Printf.sprintf "cannot find '%s' in scope" name);
            ignore (infer value)
        | Some (t, is_var) ->
            if not is_var then
              err span (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant" name);
            check_expr value t)
    | Ast.Expr_stmt (e, _) -> ignore (infer e)
  in
  List.iter check_stmt prog.Ast.stmts
