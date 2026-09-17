(* Sema — concept 05 (skeleton): the bidirectional type checker.

   You implement the TODO(05) holes. The two judgments:
     infer context expression        -> Tast.expr   synthesize a type (no expectation)
     check_expr context expression t -> Tast.expr   check against an expected type t

   Both RETURN A TYPED NODE, and that is the architecture, not a detail. A checker does not
   merely approve a program — it PRODUCES one: a `Tast.program` (see `tast.ml`) where every node
   carries its type and every name is resolved. Concept 08's SILGen consumes that tree and
   re-derives nothing, which is what stops the two stages from ever disagreeing. PLAN.md §0.1
   records what happened before, when they could.

   `infer` returns the node alone, not a (type, node) pair: the type is ON the node, so
   `(infer c e).Tast.ty` is the answer. swiftc reads it the same way — `E->getType()`.

   The one coercion is Swift's `ExpressibleByIntegerLiteral`: an *integer literal* (recursively,
   an arithmetic expression of integer literals) may take type Double when a Double is expected —
   so `let d: Double = 1 + 2` works, but `let d: Double = i` (i: Int) does not. Full literal
   flexibility is a constraint-solver job (Phase 5); we special-case the common shapes. Crucially
   the choice is RECORDED: the literal node comes back with `ty = TDouble`. Check yourself against
   the oracle — `swiftc -dump-ast` on `let d = 1.5; print(d * 2)` prints
   `integer_literal_expr type="Double"`.

   Everything is top-level and takes an explicit [context] rather than closing over a hidden
   environment, so every hole below can be unit-tested on its own — see `tests/test_units.ml`.
   No `rec` is written for you: that is a claim about the body you are about to write, and the
   compiler will tell you the moment you need one. The scaffolding is the SHAPE of the checker;
   every rule inside it is yours. Diagnostics are compared against swiftc's wording by the
   tests, so the messages named in each hole must be produced exactly. Walk-through: §3. *)

type context = {
  environment : (string, Types.ty * bool) Hashtbl.t;
      (* name -> its type, and whether it is a `var` *)
  diagnostics : Diagnostics.sink;
}

let create (diagnostics : Diagnostics.sink) : context =
  { environment = Hashtbl.create 16; diagnostics }

let report_error (context : context) span msg =
  Diagnostics.error context.diagnostics span msg

(* build a typed node — given, so the holes below read as rules rather than as record syntax *)
let mk (e : Tast.expr_kind) (ty : Types.ty) (span : Token.span) : Tast.expr = { Tast.e; ty; span }

(* TODO(05a): is [expression] an *integer literal* for coercion purposes? `1` and `1 + 2` are; an
   Int-typed variable is not — that asymmetry is the whole point of the rule. Mind which
   operators belong: Swift has no `%` on Double, so a tree containing one can never take it. *)
let is_int_literal (expression : Ast.expr) : bool =
  ignore expression;
  failwith "TODO(05a): is_int_literal"

(* TODO(05b): reconcile a binary operator's two operand types. [Some t] when both sides can be
   [t] — possibly by letting ONE side flex from Int-literal to Double — and [None] when they
   cannot. It does not decide whether the OPERATOR accepts [t], and it reports nothing: the
   caller turns a [None] into the diagnostic. §2 has the table of cases. *)
let unify (l : Ast.expr) (tl : Types.ty) (r : Ast.expr) (tr : Types.ty) :
    Types.ty option =
  ignore (l, tl, r, tr);
  failwith "TODO(05b): unify"

let infer (context : context) (expression : Ast.expr) : Tast.expr =
  match expression with
  (* literals synthesize their own type — given, as the shape for the rest. Note the node is
     BUILT here, not merely approved: that is what every arm below must also do. *)
  | Ast.Int_lit (n, span) -> mk (Tast.Int_lit n) Types.TInt span
  | Ast.Double_lit (f, span) -> mk (Tast.Double_lit f) Types.TDouble span
  | Ast.Bool_lit (b, span) -> mk (Tast.Bool_lit b) Types.TBool span
  | Ast.String_lit (s, span) -> mk (Tast.String_lit s) Types.TString span
  (* TODO(05c): the rest of the synthesis direction. Each arm returns a `Tast` node, and the
     node you choose is a RESOLUTION — it records which of several readings the name had.
       Var       look up `context.environment`, else "cannot find '%s' in scope".
                 A found name becomes `Tast.Local`: downstream, that node can only be a binding.
       Unary Neg the operand must be numeric, and keeps its type; otherwise
                 "unary operator '-' cannot be applied to an operand of type 'X'"
       Binary    the operator table in §2, via [unify]; the two failure wordings are
                 "binary operator '%s' cannot be applied to operands of type 'X' and 'Y'"
                 and, when both sides agree, "... cannot be applied to two 'X' operands".
                 When [unify] let one side flex, CHECK that side again at the unified type so
                 its literals come back carrying it — the solver decides, then a walk writes the
                 decision into the tree. That second walk is swiftc's CSApply in miniature.
       Call      only `print`, and exactly one argument of any type; the wrong count is
                 "print(_:) expects exactly one argument" (ours — Swift's print is
                 variadic), and any OTHER name is "cannot find '%s' in scope", the same
                 message an unknown variable gets. Infer the arguments either way. A real
                 call becomes `Tast.Print`.
     TODO(05g): `Ascribe (expression, tyname, span)` — `expression as T`.
       Resolve the name with `Types.of_name`
       ("cannot find type '%s' in scope" if unknown) and CHECK the operand against it, then
       wrap it in `Tast.Coerce`. This is the one arm where `infer` calls `check_expr`, which is
       what makes the two judgments mutually recursive — see §2. (swiftc keeps this node too:
       `swiftc -dump-ast` on `1 as Double` shows a `coerce_expr` around the literal.) *)
  | _ ->
      ignore (context, unify, report_error, is_int_literal);
      failwith "TODO(05c): infer"

(* TODO(05d): the checking direction — where an expectation is pushed DOWN.
     Int_lit   checks against Int *or* Double (this is the coercion, at its source) — and the
               node it returns must CARRY the expected type, because that is the record of the
               choice. This one line is why SILGen never has to guess.
     Binary    arithmetic against a numeric expectation: push it into both operands
     otherwise infer, compare, and on a mismatch report
               "cannot convert value of type 'X' to specified type 'Y'"
   It falls back to [infer], and [infer] calls it back for `as` — see TODO(05g). *)
let check_expr (context : context) (expression : Ast.expr) (expected : Types.ty)
    : Tast.expr =
  ignore (context, expression, expected, infer);
  failwith "TODO(05d): check_expr"

(* TODO(05e): one statement, returning its `Tast` form.
     Let/Var    annotated? resolve the name with `Types.of_name` ("cannot find type '%s' in
                scope" if unknown) and [check_expr] the value against it; otherwise [infer].
                Either way bind name -> (type, is_var) in `context.environment`. The annotation
                does not survive into the `Tast`: it was a written NAME, and `value.ty` is the
                resolved answer.
     Assign     the target must exist, must be a `var` — "cannot assign to value: '%s' is a
                'let' constant" — and the value must check against its type.
     Expr_stmt  infer it. *)
let check_stmt (context : context) (s : Ast.stmt) : Tast.stmt =
  ignore (context, s, infer, check_expr);
  failwith "TODO(05e): check_stmt"

(* The checker's output IS a program — given. `None` when it found errors: a tree that failed to
   check has no meaning, and making that a type rather than a convention means no later stage can
   be handed one by accident. *)
let check (program : Ast.program) (diagnostics : Diagnostics.sink) : Tast.program option =
  let context = create diagnostics in
  let stmts = List.map (check_stmt context) program.Ast.stmts in
  if Diagnostics.has_errors diagnostics then None else Some { Tast.stmts }
