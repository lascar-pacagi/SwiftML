(* FROZEN SOLUTION — concept 05 sema, WITH §6's EXERCISES 2, 3 and 5 APPLIED.
   Run it with `make check-exercises C=phase2-types-flow/05-types-inference`.
   Exercise 1 is in solution/exercises/parser.ml, exercise 4 in .../lexer.ml, and
   exercise 5's TError in .../types.ml. Every difference below is marked EX<n>.

   The bidirectional type checker.

   Two modes, mutually recursive:
     infer expression        -> Tast.expr   synthesize a type (no expectation)
     check_expr expression t -> Tast.expr   check against an expected type t (pushes t down)

   Both RETURN A TYPED NODE. That is the architecture in one line: the checker does not
   merely approve the program, it produces one — a `Tast.program` where every node
   carries its type and every name is resolved. Concept 08's SILGen consumes that and
   re-derives nothing. PLAN.md §0.1 records why, and what happened when it did.

   Note `infer` returns just the node, not a (type, node) pair: the type is ON the node, so
   `(infer c e).Tast.ty` is the answer. swiftc reads it the same way — `E->getType()`.

   The one coercion is Swift's `ExpressibleByIntegerLiteral`: an *integer literal*
   (recursively, an arithmetic expression of integer literals) may take type Double when
   a Double is expected — so `let d: Double = 1 + 2` works, but `let d: Double = i`
   (i: Int) does not. And it is recorded, not re-derived: the literal node comes back
   with `ty = TDouble`, exactly as `swiftc -dump-ast` shows for `d * 2`
   (`integer_literal_expr type="Double"`).

   Everything is top-level and takes an explicit [context], so every piece can be
   unit-tested on its own: the two pure helpers directly, the judgments against a
   context you build. *)

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
let mk (e : Tast.expr_kind) (ty : Types.ty) (span : Token.span) : Tast.expr =
  { Tast.e; ty; span }

(* A "pure integer-literal" expression can flex to Double. Note `%` is NOT in the
   list: Swift has no `%` on Double ("'%' is unavailable: For floating point numbers
   use truncatingRemainder"), so a tree containing one can never take type Double. *)
let rec is_int_literal = function
  | Ast.Int_lit _ -> true
  | Ast.Unary (Ast.Neg, expression, _) -> is_int_literal expression
  | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div), a, b, _) ->
      is_int_literal a && is_int_literal b
  | _ -> false

(* unify two operands' types, letting an integer literal become Double *)
(* EX5: an error type that still triggers diagnostics has only renamed the problem, so
   every rule that could report has to learn to keep quiet when it sees one. This is the
   first of the three places: TError unifies with anything. *)
let unify l tl r tr : Types.ty option =
  if tl = Types.TError || tr = Types.TError then Some Types.TError
  else if Types.equal tl tr then Some tl
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
      (* RESOLUTION: `Ast.Var` is a name that may or may not mean anything;
         `Tast.Local` is a binding that does. Nothing downstream re-asks. *)
      match Hashtbl.find_opt context.environment x with
      | Some (t, _) -> mk (Tast.Local x) t span
      | None ->
          report_error context span (Printf.sprintf "cannot find '%s' in scope" x);
          (* EX5: TError, not the invented TInt that used to make `nope + true` fail the
             operator rule as well and report twice where swiftc reports once. *)
          mk (Tast.Local x) Types.TError span)
  | Ast.Unary (Ast.Neg, e0, span) ->
      let n = infer context e0 in
      (* EX5: is_numeric accepts TError, so this guard is already quiet on one *)
      if not (Types.is_numeric n.Tast.ty) then
        report_error context span
          (Printf.sprintf "unary operator '-' cannot be applied to an operand of type '%s'"
             (Types.string_of_ty n.Tast.ty));
      mk (Tast.Unary (Ast.Neg, n)) n.Tast.ty span
  | Ast.Binary (op, l, r, span) -> infer_binary context op l r span
  | Ast.Call (f, args, span) -> infer_call context f args span
  (* The one place `infer` calls `check`: the type is written down, so there is nothing
     to synthesise — the operand is CHECKED against it, which is what lets
     `1 as Double` work and `i as Double` fail. swiftc keeps a `coerce_expr` too. *)
  | Ast.Ascribe (e0, tyname, span) -> (
      match Types.of_name tyname with
      | Some t -> mk (Tast.Coerce (check_expr context e0 t)) t span
      | None ->
          report_error context span
            (Printf.sprintf "cannot find type '%s' in scope" tyname);
          let n = infer context e0 in
          mk (Tast.Coerce n) n.Tast.ty span)

and infer_binary context op l r span : Tast.expr =
  (* `let … in let …`, not `let … and …`: both sides can REPORT, and OCaml leaves the
     evaluation order of `and` bindings unspecified — the order two diagnostics come out
     in is not something to leave to the compiler. *)
  let ln = infer context l in
  let rn = infer context r in
  let tl = ln.Tast.ty and tr = rn.Tast.ty in
  let bad () =
    (* EX5: the guard that is the whole exercise. One of these is already an error, so
       whatever is wrong here was reported where it went wrong. *)
    if tl = Types.TError || tr = Types.TError then ()
    else
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
  (* APPLY the solution: if a side had to flex, re-check it AT the unified type so its
     literal nodes come back carrying that type. This is CSApply's job — the solver
     decides, then a walk writes the decision into the tree. Without it the literal
     would still say TInt and SILGen would have to notice: PLAN.md §0.1's bug. *)
  let ln, rn =
    match unified with
    | Some t ->
        ( (if Types.equal tl t then ln else check_expr context l t),
          if Types.equal tr t then rn else check_expr context r t )
    | None -> (ln, rn)
  in
  (* Match on the UNIFIED type, not on tl/tr: the coercion happens inside [unify], so a
     guard over the raw operand types cannot see it — `1 == 2.0` would look like Int vs
     Double and be rejected, and `i + 2.0` acceptable until [unify] returned None. *)
  let result =
    match (unified, op) with
    | Some t, Ast.Add when Types.is_numeric t -> t
    | Some Types.TString, Ast.Add -> Types.TString (* `+` concatenates *)
    | Some t, (Ast.Sub | Ast.Mul | Ast.Div) when Types.is_numeric t -> t
    | Some Types.TInt, Ast.Mod -> Types.TInt (* no `%` on Double, as in Swift *)
    | Some _, (Ast.Eq | Ast.Ne) -> Types.TBool (* any single type may be compared *)
    | Some t, (Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge) when is_ordered t -> Types.TBool
    (* Everything else is an error. The recovery type differs: a failed comparison is
       still a Bool, or the enclosing `if` reports a problem nobody wrote. *)
    | _, (Ast.Eq | Ast.Ne | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge) ->
        bad ();
        Types.TBool
    | _ ->
        bad ();
        (* EX5: propagate the error rather than inventing an Int for the parent to trip
           over next. A comparison stays TBool above: that arm is a real Bool-shaped hole
           and the enclosing `if` should not report a problem nobody wrote. *)
        if tl = Types.TError || tr = Types.TError then Types.TError else Types.TInt
  in
  mk (Tast.Binary (op, ln, rn)) result span

and infer_call context f args span : Tast.expr =
  (* EX2: the two explicit conversions, taken before `print`. They are what makes
     `let d: Double = Double(i)` work where the bare `let d: Double = i` does not — in
     Swift a widening conversion is something you WRITE, never something that happens to
     you, which is the whole reason check_expr only ever flexes literals.

     An honest wrinkle, and §2's argument arriving in a rule you wrote. Tast.Coerce is
     borrowed because concept 05 has no node of its own for this, and it passes here
     because nothing runs the code yet. But `1 as Double` only changes what a literal IS,
     while `Double(i)` has to convert a value at run time — an `sitofp`, once concept 09
     emits LLVM. A real version adds `Tast.Num_conv of expr` precisely so the back end is
     TOLD a conversion happens instead of having to infer it from the operand types. *)
  let numeric_conversion (target : Types.ty) =
    match args with
    | [ a ] ->
        let n = infer context a in
        if not (Types.is_numeric n.Tast.ty) then
          report_error context span
            (Printf.sprintf
               "cannot convert value of type '%s' to expected argument type '%s'"
               (Types.string_of_ty n.Tast.ty)
               (Types.string_of_ty target));
        mk (Tast.Coerce n) target span
    | _ ->
        report_error context span
          (Printf.sprintf "%s(_:) expects exactly one argument"
             (Types.string_of_ty target));
        let ns = List.map (infer context) args in
        let first =
          match ns with n :: _ -> n | [] -> mk (Tast.Int_lit 0) target span
        in
        mk (Tast.Coerce first) target span
  in
  if f = "Double" then numeric_conversion Types.TDouble
  else if f = "Int" then numeric_conversion Types.TInt
    (* RESOLUTION: `print` is the only other function this subset has, so a call either IS
       print, or is a conversion, or is an unknown name. `Tast.Print` records which —
       SILGen never has to ask. *)
  else if f = "print" then
    match args with
    | [ a ] -> mk (Tast.Print (infer context a)) Types.TInt span
    | _ ->
        report_error context span "print(_:) expects exactly one argument";
        let ns = List.map (infer context) args in
        let first =
          match ns with n :: _ -> n | [] -> mk (Tast.Int_lit 0) Types.TInt span
        in
        mk (Tast.Print first) Types.TInt span
  else (
    report_error context span (Printf.sprintf "cannot find '%s' in scope" f);
    let ns = List.map (infer context) args in
    mk (Tast.Print (match ns with n :: _ -> n | [] -> mk (Tast.Int_lit 0) Types.TInt span))
      Types.TInt span)
(* The checking direction — and the other half of a genuine knot: [check_expr] falls
   back to [infer], and [infer] calls [check_expr] for `expression as T`. Neither can be
   defined without the other: "mutually recursive", in practice. *)

and check_expr (context : context) (expression : Ast.expr) (expected : Types.ty) :
    Tast.expr =
  match expression with
  | Ast.Int_lit (n, span) ->
      (* An integer literal is ExpressibleBy both Int and Double — and THIS is where the
         choice is recorded. The node keeps its kind and takes the expected type, just as
         `swiftc -dump-ast` shows: `integer_literal_expr type="Double"`. *)
      if expected = Types.TInt || expected = Types.TDouble then
        mk (Tast.Int_lit n) expected span
      else (
        report_error context span
          (Printf.sprintf "cannot convert value of type 'Int' to specified type '%s'"
             (Types.string_of_ty expected));
        mk (Tast.Int_lit n) Types.TInt span)
  | Ast.Binary (((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div) as op), l, r, span)
    when Types.is_numeric expected ->
      (* push the expected numeric type into both operands: 1 + 2 checks as Double *)
      let l = check_expr context l expected in
      let r = check_expr context r expected in
      mk (Tast.Binary (op, l, r)) expected span
  | Ast.Binary (Ast.Mod, l, r, span) when expected = Types.TInt ->
      let l = check_expr context l Types.TInt in
      let r = check_expr context r Types.TInt in
      mk (Tast.Binary (Ast.Mod, l, r)) Types.TInt span
  | Ast.Unary (Ast.Neg, e0, span) when Types.is_numeric expected ->
      mk (Tast.Unary (Ast.Neg, check_expr context e0 expected)) expected span
  | _ ->
      let n = infer context expression in
      (* EX5: the third guard. TError has already been reported where it was made. *)
      if
        (not (Types.equal n.Tast.ty expected))
        && n.Tast.ty <> Types.TError
        && expected <> Types.TError
      then
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
            (* EX3: the second location. The ERROR already sits where swiftc puts it —
               `swiftc -typecheck` on `let x: Int = "s"` points at column 14, the value,
               and so do we — so the exercise is not to move it. What neither compiler
               says is where the expectation came from, and that is the declaration.

               It is emitted here rather than in check_expr because check_expr is handed
               a type, not a statement: it has no span to point at but the one it is
               already reporting on, and a note on top of its own error says nothing.
               Counting the sink is the crude part, and the honest way to read it is
               "did checking the value complain?" — Diagnostics has no richer answer. *)
            | Some t ->
                let before = List.length (Diagnostics.all context.diagnostics) in
                let n = check_expr context value t in
                if List.length (Diagnostics.all context.diagnostics) > before then
                  Diagnostics.emit context.diagnostics
                    {
                      Diagnostics.severity = Diagnostics.Note;
                      span;
                      message =
                        Printf.sprintf "'%s' is declared as '%s' here" name tyname;
                    };
                n
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

(* The checker's output IS a program. `None` when it found errors: a tree that failed
   to check has no meaning, and making that a *type* rather than a convention means no
   later stage can be handed one by accident. *)
let check (program : Ast.program) (diagnostics : Diagnostics.sink) : Tast.program option =
  let context = create diagnostics in
  let stmts = List.map (check_stmt context) program.Ast.stmts in
  if Diagnostics.has_errors diagnostics then None else Some { Tast.stmts }
