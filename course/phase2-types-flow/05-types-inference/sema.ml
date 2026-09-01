(* Sema — concept 05 (skeleton): the bidirectional type checker.

   You implement the TODO(05) holes. The two judgments:
     infer cx e        -> ty      synthesize a type (no expectation)
     check_expr cx e t -> unit    check e against an expected type t (pushes t down)

   The one coercion is Swift's `ExpressibleByIntegerLiteral`: an *integer literal*
   (recursively, an arithmetic expression of integer literals) may take type Double when a
   Double is expected — so `let d: Double = 1 + 2` works, but `let d: Double = i` (i: Int)
   does not. Full literal flexibility is a constraint-solver job (Phase 5); we special-case
   the common shapes.

   Everything is top-level and takes an explicit [ctx] rather than closing over a hidden
   environment, so every hole below can be unit-tested on its own — see `tests/test_units.ml`.
   No `rec` is written for you: that is a claim about the body you are about to write, and the
   compiler will tell you the moment you need one. The scaffolding is the SHAPE of the checker;
   every rule inside it is yours. Diagnostics are compared against swiftc's wording by the
   tests, so the messages named in each hole must be produced exactly. Walk-through: §3. *)

type ctx = {
  env : (string, Types.ty * bool) Hashtbl.t;  (* name -> its type, and whether it is a `var` *)
  diags : Diagnostics.sink;
}

let create (diags : Diagnostics.sink) : ctx = { env = Hashtbl.create 16; diags }
let err (cx : ctx) span msg = Diagnostics.error cx.diags span msg

(* TODO(05a): is [e] an *integer literal* for coercion purposes? `1` and `1 + 2` are; an
   Int-typed variable is not — that asymmetry is the whole point of the rule. *)
let is_int_literal (e : Ast.expr) : bool =
  ignore e;
  failwith "TODO(05a): is_int_literal"

(* TODO(05b): reconcile a binary operator's two operand types. [Some t] when both sides can be
   [t] — possibly by letting ONE side flex from Int-literal to Double — and [None] when they
   cannot. It does not decide whether the OPERATOR accepts [t], and it reports nothing: the
   caller turns a [None] into the diagnostic. §2 has the table of cases. *)
let unify (l : Ast.expr) (tl : Types.ty) (r : Ast.expr) (tr : Types.ty) : Types.ty option =
  ignore (l, tl, r, tr);
  failwith "TODO(05b): unify"

let infer (cx : ctx) (e : Ast.expr) : Types.ty =
  match e with
  (* literals synthesize their own type — given, as the shape for the rest *)
  | Ast.Int_lit _ -> Types.TInt
  | Ast.Double_lit _ -> Types.TDouble
  | Ast.Bool_lit _ -> Types.TBool
  | Ast.String_lit _ -> Types.TString
  (* TODO(05c): the rest of the synthesis direction.
       Var       look up `cx.env`, else "cannot find '%s' in scope"
       Unary Neg the operand must be numeric, and keeps its type; otherwise
                 "unary operator '-' cannot be applied to an operand of type 'X'"
       Binary    the operator table in §2, via [unify]; the two failure wordings are
                 "binary operator '%s' cannot be applied to operands of type 'X' and 'Y'"
                 and, when both sides agree, "... cannot be applied to two 'X' operands"
       Call      only `print`, exactly one argument, any type
     TODO(05g): `Ascribe (e, tyname, span)` — `e as T`. Resolve the name with `Types.of_name`
       ("cannot find type '%s' in scope" if unknown) and CHECK the operand against it, then
       return it. This is the one arm where `infer` calls `check_expr`, which is what makes the
       two judgments mutually recursive — see §2. *)
  | _ ->
      ignore (cx, unify, err);
      failwith "TODO(05c): infer"

(* TODO(05d): the checking direction — where an expectation is pushed DOWN.
     Int_lit   checks against Int *or* Double (this is the coercion, at its source)
     Binary    arithmetic against a numeric expectation: push it into both operands
     otherwise infer, compare, and on a mismatch report
               "cannot convert value of type 'X' to specified type 'Y'"
   It falls back to [infer]; [infer] never calls back, so the two are not mutually
   recursive in this subset (in a fuller language they would be). *)
let check_expr (cx : ctx) (e : Ast.expr) (expected : Types.ty) : unit =
  ignore (cx, e, expected, infer);
  failwith "TODO(05d): check_expr"

(* TODO(05e): one statement.
     Let/Var    annotated? resolve the name with `Types.of_name` ("cannot find type '%s' in
                scope" if unknown) and [check_expr] the value against it; otherwise [infer].
                Either way bind name -> (type, is_var) in `cx.env`.
     Assign     the target must exist, must be a `var` — "cannot assign to value: '%s' is a
                'let' constant" — and the value must check against its type.
     Expr_stmt  infer it and discard the type. *)
let check_stmt (cx : ctx) (s : Ast.stmt) : unit =
  ignore (cx, s, infer, check_expr);
  failwith "TODO(05e): check_stmt"

let check (prog : Ast.program) (diags : Diagnostics.sink) : unit =
  let cx = create diags in
  List.iter (check_stmt cx) prog.Ast.stmts
