(* FROZEN SOLUTION — concept 05 sema: the bidirectional type checker.

   Two modes, mutually recursive:
     infer expression        -> Tast.expr   synthesize a type (no expectation)
     check_expr expression t -> Tast.expr   check against an expected type t (pushes t down)

   Both RETURN A TYPED NODE. That is the whole architecture in one line: the checker does not
   merely approve the program, it produces one — a `Tast.program` where every node carries its
   type and every name is resolved. Concept 08's SILGen consumes that and re-derives nothing.
   PLAN.md §0.1 records why, with the history of what happened when it did re-derive.

   Note `infer` returns just the node, not a (type, node) pair: the type is ON the node, so
   `(infer c e).Tast.ty` is the answer. swiftc reads it the same way — `E->getType()`.

   The one coercion is Swift's `ExpressibleByIntegerLiteral`: an *integer literal* (recursively,
   an arithmetic expression of integer literals) may take type Double when a Double is expected —
   so `let d: Double = 1 + 2` works, but `let d: Double = i` (i: Int) does not. And it is
   recorded, not re-derived: the literal node comes back with `ty = TDouble`. That is exactly
   what `swiftc -dump-ast` shows for `d * 2` — `integer_literal_expr type="Double"`.

   Everything is top-level and takes an explicit [context], so every piece can be unit-tested on
   its own: the two pure helpers directly, the judgments against a context you build. *)

type context = {
  environment : (string, Types.ty * bool) Hashtbl.t;
      (* name -> its type, and whether it is a `var` *)
  diagnostics : Diagnostics.sink;
}

let create (diagnostics : Diagnostics.sink) : context =
  { environment = Hashtbl.create 16; diagnostics }

let report_error (context : context) span msg =
  Diagnostics.error context.diagnostics span msg

(* build a typed node — the one place a `Tast.expr` is made *)
let mk (e : Tast.expr_kind) (ty : Types.ty) (span : Token.span) : Tast.expr = { Tast.e; ty; span }

(* A "pure integer-literal" expression can flex to Double. Note `%` is NOT in the list: Swift has
   no `%` on Double ("'%' is unavailable: For floating point numbers use truncatingRemainder"),
   so a tree containing one can never take type Double. *)
let rec is_int_literal = function
  | Ast.Int_lit _ -> true
  | Ast.Unary (Ast.Neg, expression, _) -> is_int_literal expression
  | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div), a, b, _) ->
      is_int_literal a && is_int_literal b
  | _ -> false

(* unify two operands' types, letting an integer literal become Double *)
let unify l tl r tr : Types.ty option =
  if Types.equal tl tr then Some tl
  else if is_int_literal l && tr = Types.TDouble then Some Types.TDouble
  else if is_int_literal r && tl = Types.TDouble then Some Types.TDouble
  else None

let rec infer (context : context) (expression : Ast.expr) : Tast.expr =
  match expression with
  | Ast.Int_lit (n, span) -> mk (Tast.Int_lit n) Types.TInt span
  | Ast.Double_lit (f, span) -> mk (Tast.Double_lit f) Types.TDouble span
  | Ast.Bool_lit (b, span) -> mk (Tast.Bool_lit b) Types.TBool span
  | Ast.String_lit (s, span) -> mk (Tast.String_lit s) Types.TString span
  | Ast.Var (x, span) -> (
      (* RESOLUTION: `Ast.Var` is a name that may or may not mean anything; `Tast.Local` is a
         binding that does. Nothing downstream has to ask this question again. *)
      match Hashtbl.find_opt context.environment x with
      | Some (t, _) -> mk (Tast.Local x) t span
      | None ->
          report_error context span (Printf.sprintf "cannot find '%s' in scope" x);
          mk (Tast.Local x) Types.TInt span)
  | Ast.Unary (Ast.Neg, e0, span) ->
      let n = infer context e0 in
      if not (Types.is_numeric n.Tast.ty) then
        report_error context span
          (Printf.sprintf "unary operator '-' cannot be applied to an operand of type '%s'"
             (Types.string_of_ty n.Tast.ty));
      mk (Tast.Unary (Ast.Neg, n)) n.Tast.ty span
  | Ast.Binary (op, l, r, span) -> infer_binary context op l r span
  | Ast.Call (f, args, span) -> infer_call context f args span
  (* The one place `infer` calls `check`: the type is written down, so there is nothing to
     synthesise — the operand is CHECKED against it, which is what lets `1 as Double` work and
     `i as Double` fail. swiftc keeps a `coerce_expr` node here too. *)
  | Ast.Ascribe (e0, tyname, span) -> (
      match Types.of_name tyname with
      | Some t -> mk (Tast.Coerce (check_expr context e0 t)) t span
      | None ->
          report_error context span (Printf.sprintf "cannot find type '%s' in scope" tyname);
          let n = infer context e0 in
          mk (Tast.Coerce n) n.Tast.ty span)

and infer_binary context op l r span : Tast.expr =
  let ln = infer context l and rn = infer context r in
  let tl = ln.Tast.ty and tr = rn.Tast.ty in
  let bad () =
    (* swiftc has two wordings, and picks by whether the operands agree:
           1 + true     -> cannot be applied to operands of type 'Int' and 'Bool'
           true < false -> cannot be applied to two 'Bool' operands *)
    report_error context span
      (if tl = tr then
         Printf.sprintf "binary operator '%s' cannot be applied to two '%s' operands"
           (Ast.string_of_binop op) (Types.string_of_ty tl)
       else
         Printf.sprintf
           "binary operator '%s' cannot be applied to operands of type '%s' and '%s'"
           (Ast.string_of_binop op) (Types.string_of_ty tl) (Types.string_of_ty tr))
  in
  let is_ordered t = Types.is_numeric t || t = Types.TString in
  let unified = unify l tl r tr in
  (* APPLY the solution: if a side had to flex, re-check it AT the unified type so its literal
     nodes come back carrying that type. This is CSApply's job — the solver decides, then a walk
     writes the decision into the tree. Without it the literal would still say TInt and SILGen
     would have to notice, which is the bug PLAN.md §0.1 is about. *)
  let ln, rn =
    match unified with
    | Some t ->
        ( (if Types.equal tl t then ln else check_expr context l t),
          if Types.equal tr t then rn else check_expr context r t )
    | None -> (ln, rn)
  in
  (* Match on the UNIFIED type, not on tl/tr: the coercion happens inside [unify], so a guard
     over the raw operand types cannot see it — `1 == 2.0` would look like Int vs Double and be
     rejected, and `i + 2.0` would look acceptable right up until [unify] returned None. *)
  let result =
    match (unified, op) with
    | Some t, Ast.Add when Types.is_numeric t -> t
    | Some Types.TString, Ast.Add -> Types.TString (* `+` concatenates *)
    | Some t, (Ast.Sub | Ast.Mul | Ast.Div) when Types.is_numeric t -> t
    | Some Types.TInt, Ast.Mod -> Types.TInt (* no `%` on Double, as in Swift *)
    | Some _, (Ast.Eq | Ast.Ne) -> Types.TBool (* any single type may be compared *)
    | Some t, (Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge) when is_ordered t -> Types.TBool
    (* Everything else is an error. The recovery type differs: a failed comparison is still a
       Bool, or the enclosing `if` reports a second problem nobody wrote. *)
    | _, (Ast.Eq | Ast.Ne | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge) ->
        bad ();
        Types.TBool
    | _ ->
        bad ();
        Types.TInt
  in
  mk (Tast.Binary (op, ln, rn)) result span

and infer_call context f args span : Tast.expr =
  (* RESOLUTION: `print` is the only function this subset has, so a call either IS print or is an
     unknown name. `Tast.Print` records which — SILGen never has to ask. *)
  if f = "print" then
    match args with
    | [ a ] -> mk (Tast.Print (infer context a)) Types.TInt span
    | _ ->
        report_error context span "print(_:) expects exactly one argument";
        let ns = List.map (infer context) args in
        mk (Tast.Print (match ns with n :: _ -> n | [] -> mk (Tast.Int_lit 0) Types.TInt span))
          Types.TInt span
  else (
    report_error context span (Printf.sprintf "cannot find '%s' in scope" f);
    let ns = List.map (infer context) args in
    mk (Tast.Print (match ns with n :: _ -> n | [] -> mk (Tast.Int_lit 0) Types.TInt span))
      Types.TInt span)
(* The checking direction — and the other half of a genuine knot: [check_expr] falls back to
   [infer], and [infer] calls [check_expr] for `expression as T`. Neither can be defined without
   the other, which is what "the two judgments are mutually recursive" means in practice. *)

and check_expr (context : context) (expression : Ast.expr) (expected : Types.ty) : Tast.expr =
  match expression with
  | Ast.Int_lit (n, span) ->
      (* An integer literal is ExpressibleBy both Int and Double — and THIS is where the choice
         is recorded. The node keeps its kind and takes the expected type, exactly as
         `swiftc -dump-ast` shows: `integer_literal_expr type="Double"`. *)
      if expected = Types.TInt || expected = Types.TDouble then mk (Tast.Int_lit n) expected span
      else (
        report_error context span
          (Printf.sprintf "cannot convert value of type 'Int' to specified type '%s'"
             (Types.string_of_ty expected));
        mk (Tast.Int_lit n) Types.TInt span)
  | Ast.Binary (((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div) as op), l, r, span)
    when Types.is_numeric expected ->
      (* push the expected numeric type into both operands: 1 + 2 checks as Double *)
      mk (Tast.Binary (op, check_expr context l expected, check_expr context r expected)) expected span
  | Ast.Binary (Ast.Mod, l, r, span) when expected = Types.TInt ->
      mk
        (Tast.Binary (Ast.Mod, check_expr context l Types.TInt, check_expr context r Types.TInt))
        Types.TInt span
  | Ast.Unary (Ast.Neg, e0, span) when Types.is_numeric expected ->
      mk (Tast.Unary (Ast.Neg, check_expr context e0 expected)) expected span
  | _ ->
      let n = infer context expression in
      if not (Types.equal n.Tast.ty expected) then
        report_error context (Ast.expr_span expression)
          (Printf.sprintf "cannot convert value of type '%s' to specified type '%s'"
             (Types.string_of_ty n.Tast.ty) (Types.string_of_ty expected));
      n

let check_stmt (context : context) (s : Ast.stmt) : Tast.stmt =
  match s with
  | Ast.Let { name; is_var; annot; value; span } ->
      let n =
        match annot with
        | None -> infer context value
        | Some tyname -> (
            match Types.of_name tyname with
            | Some t -> check_expr context value t
            | None ->
                report_error context span
                  (Printf.sprintf "cannot find type '%s' in scope" tyname);
                infer context value)
      in
      Hashtbl.replace context.environment name (n.Tast.ty, is_var);
      Tast.Let { name; is_var; value = n; span }
  | Ast.Assign { name; value; span } -> (
      match Hashtbl.find_opt context.environment name with
      | None ->
          report_error context span (Printf.sprintf "cannot find '%s' in scope" name);
          Tast.Assign { name; value = infer context value; span }
      | Some (t, is_var) ->
          if not is_var then
            report_error context span
              (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant" name);
          Tast.Assign { name; value = check_expr context value t; span })
  | Ast.Expr_stmt (expression, _) -> Tast.Expr_stmt (infer context expression)

(* The checker's output IS a program. `None` when it found errors: a tree that failed to check
   has no meaning, and making that a type rather than a convention means no later stage can be
   handed one by accident. *)
let check (program : Ast.program) (diagnostics : Diagnostics.sink) : Tast.program option =
  let context = create diagnostics in
  let stmts = List.map (check_stmt context) program.Ast.stmts in
  if Diagnostics.has_errors diagnostics then None else Some { Tast.stmts }
