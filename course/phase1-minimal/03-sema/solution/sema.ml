(* FROZEN SOLUTION — concept 03-sema. Verified answer key for [sema.ml].
   Kept out of the build by `(dirs :standard \ solution)`. Verify by copying over
   ../sema.ml and running `dune build @phase1-minimal/03-sema/runtest`.

   Phase 1 is trivial — the only type is Int — so this mostly checks name resolution:
   every variable is declared before use, assignment targets exist and are mutable,
   and print(_:) is called with one argument. Grows into a real bidirectional checker
   (Phase 2) and toward the constraint solver (Phase 5).

   Design oracle:
     swift/lib/Sema/TypeCheckDecl.cpp  TypeCheckExpr.cpp  TypeCheckStmt.cpp *)

(* The Phase-1 type lattice: just Int. (Grows: Bool, Double, String, … in Phase 2.) *)
type ty = TInt

let string_of_ty = function TInt -> "Int"

let check (prog : Ast.program) (diags : Diagnostics.sink) : unit =
  (* name -> is_var (true for `var`, false for `let`). Phase 1 has one flat top-level
     scope; later phases make this a stack of scopes. *)
  let scope : (string, bool) Hashtbl.t = Hashtbl.create 16 in
  (* check_expr returns a [ty] so Phase 2 can fill in real type rules; for now it is
     always TInt and the work is pure name resolution. *)
  let rec check_expr (e : Ast.expr) : ty =
    match e with
    | Ast.Int_lit _ -> TInt
    | Ast.Var (x, span) ->
        if not (Hashtbl.mem scope x) then
          Diagnostics.error diags span (Printf.sprintf "cannot find '%s' in scope" x);
        TInt
    | Ast.Unary (_, e, _) ->
        ignore (check_expr e);
        TInt
    | Ast.Binary (_, l, r, _) ->
        ignore (check_expr l);
        ignore (check_expr r);
        TInt
    | Ast.Call (f, args, span) ->
        (* Phase 1: the only callable is the builtin print(_:). *)
        if f = "print" then (
          match args with
          | [ a ] -> ignore (check_expr a)
          | _ ->
              Diagnostics.error diags span
                "print(_:) expects exactly one argument";
              List.iter (fun a -> ignore (check_expr a)) args)
        else (
          Diagnostics.error diags span (Printf.sprintf "cannot find '%s' in scope" f);
          List.iter (fun a -> ignore (check_expr a)) args);
        TInt
  in
  let check_stmt (s : Ast.stmt) : unit =
    match s with
    | Ast.Let { name; is_var; value; _ } ->
        (* check the initializer BEFORE binding the name, so `let a = a` is an error. *)
        ignore (check_expr value);
        Hashtbl.replace scope name is_var
    | Ast.Assign { name; value; span } ->
        (match Hashtbl.find_opt scope name with
        | None ->
            Diagnostics.error diags span (Printf.sprintf "cannot find '%s' in scope" name)
        | Some is_var ->
            if not is_var then
              Diagnostics.error diags span
                (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant" name));
        ignore (check_expr value)
    | Ast.Expr_stmt (e, _) -> ignore (check_expr e)
  in
  List.iter check_stmt prog.Ast.stmts
