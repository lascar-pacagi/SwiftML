(* Sema — concept 05 (skeleton): the bidirectional type checker.

   You implement the TODO(05) holes. The two judgments, mutually recursive:
     infer e        -> ty        synthesize a type (no expectation)
     check_expr e t -> unit      check e against an expected type t (pushes t down)

   The one coercion is Swift's `ExpressibleByIntegerLiteral`: an *integer literal*
   (recursively, an arithmetic expression of integer literals) may take type Double when a
   Double is expected — so `let d: Double = 1 + 2` works, but `let d: Double = i` (i: Int)
   does not. Full literal flexibility is a constraint-solver job (Phase 5); we special-case
   the common shapes.

   Reference: solution/sema.ml. *)

let check (prog : Ast.program) (diags : Diagnostics.sink) : unit =
  let env : (string, Types.ty * bool) Hashtbl.t = Hashtbl.create 16 in
  let err span msg = Diagnostics.error diags span msg in
  ignore env;
  ignore err;
  ignore prog;
  (* TODO(05): the bidirectional type checker.

     - is_int_literal : an Int_lit, a negation of one, or an arithmetic expression of them
       (so a pure integer-literal expression can flex to Double).
     - unify l tl r tr : equal types unify; otherwise an integer-literal operand may become
       Double when the other side is Double.
     - infer : literals -> their type; Var -> env lookup (else "cannot find 'x' in scope");
       Unary '-' -> operand must be numeric; Binary -> the operator typing table; Call ->
       print(_:) takes one argument of any type and yields a placeholder.
     - check_expr e expected : Int_lit checks against Int OR Double; arithmetic Binary when
       expected is numeric pushes expected into both operands; everything else infers and
       compares ("cannot convert value of type 'X' to specified type 'Y'").
     - check_stmt : Let (annotated -> resolve + check_expr; else infer; bind name);
       Assign (must exist, be a var, value check_expr's against its type); Expr_stmt.
     Finally iterate check_stmt over prog.stmts. *)
  failwith "TODO(05): implement the bidirectional type checker in sema.ml"
