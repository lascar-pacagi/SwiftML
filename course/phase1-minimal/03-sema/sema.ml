(* Semantic analysis: name resolution + (trivial) type checking for the Phase-1 subset.

   Phase 1 is trivial — the only type is Int — so this mostly checks name resolution:
   every variable is declared before use, assignment targets exist and are mutable,
   and print(_:) is called with one argument. Grows into a real bidirectional checker
   (Phase 2) and toward the constraint solver (Phase 5).

   >>> You build this in concept  phase1-minimal/03-sema. <<<

   Design oracle:
     swift/lib/Sema/TypeCheckDecl.cpp  TypeCheckExpr.cpp  TypeCheckStmt.cpp *)

(* The Phase-1 type lattice: just Int. (Grows: Bool, Double, String, … in Phase 2.) *)
type ty = TInt

let string_of_ty = function TInt -> "Int"

(* Walk the program, resolving names and (trivially) type-checking. Report problems
   into [diags]; the driver bails before IRGen if [Diagnostics.has_errors].

     - keep a [scope : (string, bool) Hashtbl.t] mapping name -> is_var (for mutability);
     - [check_expr]: Int_lit/Unary/Binary are TInt (recurse into operands); a [Var x]
       not in scope ⇒ "cannot find '<x>' in scope"; a [Call] is only the builtin
       print(_:) — exactly one arg, else "print(_:) expects exactly one argument";
       any other callee ⇒ "cannot find '<f>' in scope";
     - [check_stmt]: a [Let] checks its initializer BEFORE binding the name (so
       `let a = a` is an error), then records [is_var]; an [Assign] target must be a
       declared, mutable binding (else "cannot find …" / "cannot assign to value:
       '<name>' is a 'let' constant"); an [Expr_stmt] just checks its expression.
   See the explainer (§3 "Build it") for the full walk-through. *)
let check (prog : Ast.program) (diags : Diagnostics.sink) : unit =
  ignore (prog, diags, string_of_ty);
  failwith "TODO(03-sema): implement Sema.check (scope + name resolution + Int typing)"
