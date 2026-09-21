(* The Phase-2 type lattice — WITH §6 EXERCISE 5 APPLIED (TError).
   Run it with `make check-exercises C=phase2-types-flow/05-types-inference`.

   Phase 1 had a single type, `TInt`. Phase 2 adds `Bool`, `Double`, `String`. There are
   still **no type variables**: concept 05 type-checks *bidirectionally* (push an expected
   type down, pull an inferred type up), which handles literal defaulting and coercion
   without inference variables. The full constraint solver (`?T0` unknowns, unification)
   is Phase 5.

   Design oracle:
     swift/include/swift/AST/Types.h      (the Type hierarchy)
     swift/lib/Sema/CSGen.cpp / CSSolver.cpp  (the constraint system — Phase 5) *)

(* EX5: TError is the type we invent after reporting, so the mistake does not travel.
   It is a BOTTOM type — compatible with everything, absorbing every operation — which is
   what makes one mistake produce one message however deeply it is nested. swiftc carries
   a HasError bit up through every composite type for the same reason (Types.h:1682). *)
type ty = TError | TInt | TBool | TDouble | TString

(* swiftc's spelling, for diagnostics: "expected 'Int', found 'String'". *)
let string_of_ty : ty -> string = function
  | TError -> "<error>"
  | TInt -> "Int"
  | TBool -> "Bool"
  | TDouble -> "Double"
  | TString -> "String"

let equal (left : ty) (right : ty) : bool = left = right

(* The arithmetic types. `+ - * /` are defined on these (and `+` also on String);
   comparisons (`< > == …`) take these and yield `TBool`. *)
let is_numeric : ty -> bool = function
  | TInt | TDouble -> true
  (* EX5: accepted anywhere a number is wanted, so no SECOND diagnostic fires *)
  | TError -> true
  | TBool | TString -> false

(* Map a type *name* as written in an annotation (`let x: Double = …`) to a type, or
   None if it isn't one of our known types (sema reports "cannot find type 'Foo'"). *)
let of_name : string -> ty option = function
  | "Int" -> Some TInt
  | "Bool" -> Some TBool
  | "Double" -> Some TDouble
  | "String" -> Some TString
  | _ -> None
