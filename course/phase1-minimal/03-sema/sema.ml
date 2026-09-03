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

(* Walk the program, resolving names and (trivially) type-checking, reporting into
   [diags] — the driver bails before IRGen if [Diagnostics.has_errors].

   Two rules are easy to get subtly wrong, and the tests pin both: an initializer is
   checked BEFORE its name is bound, and an assignment target must be declared AND
   mutable. Every diagnostic is compared against swiftc's wording.
   Walk-through: explainer §3. *)
let check (prog : Ast.program) (diags : Diagnostics.sink) : unit =
  ignore (prog, diags, string_of_ty);
  failwith "TODO(03-sema): implement Sema.check (scope + name resolution + Int typing)"
