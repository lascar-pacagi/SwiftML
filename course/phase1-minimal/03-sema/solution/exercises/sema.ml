(* FROZEN SOLUTION — concept 03-sema, WITH §6's EXERCISES APPLIED.
   Kept out of the build by `(dirs :standard \ solution)`. Run it with
   `make check-exercises C=phase1-minimal/03-sema`.

   This is `solution/sema.ml` plus exercise 1 (reject redeclaration) and exercise 2 (the
   two notes swiftc prints beside those errors). Read the stock answer key first: the
   differences are marked EX1 and EX2 below, and they are all in `scope`'s type and the
   two statement arms that read it.

   Phase 1 is trivial — the only type is Int — so this mostly checks name resolution:
   every variable is declared before use, assignment targets exist and are mutable,
   and print(_:) is called with one argument. Grows into a real bidirectional checker
   (Phase 2) and toward the constraint solver (Phase 5).

   Design oracle:
     swift/lib/Sema/TypeCheckDecl.cpp  TypeCheckExpr.cpp  TypeCheckStmt.cpp *)

(* The Phase-1 type lattice: just Int. (Grows: Bool, Double, String, … in Phase 2.) *)
type ty = TInt

let string_of_ty = function TInt -> "Int"

let check (program : Ast.program) (diagnostics : Diagnostics.sink) : unit =
  (* name -> is_var (true for `var`, false for `let`). Phase 1 has one flat top-level
     scope; later phases make this a stack of scopes.

     EX2: and the span the name was DECLARED at. Both notes point at the earlier
     declaration, not at the statement that broke the rule, so the environment has to
     remember where that was. Widening this table is a one-line type change and a
     two-line ripple — which is what every later phase does to it in turn. *)
  let scope : (string, bool * Token.span) Hashtbl.t = Hashtbl.create 16 in
  (* check_expr returns a [ty] so Phase 2 can fill in real type rules; for now it is
     always TInt and the work is pure name resolution. *)
  let rec check_expr (expression : Ast.expr) : ty =
    match expression with
    | Ast.Int_lit _ -> TInt
    | Ast.Var (x, span) ->
        if not (Hashtbl.mem scope x) then
          Diagnostics.error diagnostics span
            (Printf.sprintf "cannot find '%s' in scope" x);
        TInt
    | Ast.Unary (_, expression, _) ->
        ignore (check_expr expression);
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
              Diagnostics.error diagnostics span
                "print(_:) expects exactly one argument";
              List.iter (fun a -> ignore (check_expr a)) args)
        else (
          Diagnostics.error diagnostics span
            (Printf.sprintf "cannot find '%s' in scope" f);
          List.iter (fun a -> ignore (check_expr a)) args);
        TInt
  in
  let check_stmt (s : Ast.stmt) : unit =
    match s with
    | Ast.Let { name; is_var; value; span } ->
        (* check the initializer BEFORE binding the name, so `let a = a` is an error.
           A bad declaration is still a declaration: its value is checked either way. *)
        ignore (check_expr value);
        (* EX1: swiftc REJECTS top-level redeclaration rather than shadowing it — the
           oracle settles a question guessing gets wrong. EX2 adds the note, which is
           why this reads the binding instead of testing for it: the note goes at the
           span of the FIRST declaration. Not rebinding is what keeps that first one
           authoritative, so a later `x = 3` is judged against `let x = 1`. *)
        (match Hashtbl.find_opt scope name with
        | Some (_, previous) ->
            Diagnostics.error diagnostics span
              (Printf.sprintf "invalid redeclaration of '%s'" name);
            Diagnostics.note diagnostics previous
              (Printf.sprintf "'%s' previously declared here" name)
        | None -> Hashtbl.replace scope name (is_var, span))
    | Ast.Assign { name; value; span } ->
        (match Hashtbl.find_opt scope name with
        | None ->
            Diagnostics.error diagnostics span
              (Printf.sprintf "cannot find '%s' in scope" name)
        | Some (is_var, declared_at) ->
            if not is_var then (
              Diagnostics.error diagnostics span
                (Printf.sprintf
                   "cannot assign to value: '%s' is a 'let' constant" name);
              (* EX2: the note belongs at the `let`, which is where the fix is made *)
              Diagnostics.note diagnostics declared_at
                "change 'let' to 'var' to make it mutable"));
        ignore (check_expr value)
    | Ast.Expr_stmt (expression, _) -> ignore (check_expr expression)
  in
  List.iter check_stmt program.Ast.stmts
