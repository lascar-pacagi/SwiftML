(* The Phase-2 type lattice — a *contract*: the types themselves are given, one TODO(05)
   hole is yours (the annotation-name table at the bottom), and you implement the checker
   in sema.ml that produces and compares these).

   Phase 1 had a single type, `TInt`. Phase 2 adds `Bool`, `Double`, `String`. There are
   still **no type variables**: concept 05 type-checks *bidirectionally* (push an expected
   type down, pull an inferred type up), which handles literal defaulting and coercion
   without inference variables. The full constraint solver (`?T0` unknowns, unification)
   is Phase 5.

   Design oracle:
     swift/include/swift/AST/Types.h      (the Type hierarchy)
     swift/lib/Sema/CSGen.cpp / CSSolver.cpp  (the constraint system — Phase 5) *)

type ty =
  | TInt
  | TBool
  | TDouble
  | TString

(* swiftc's spelling, for diagnostics: "expected 'Int', found 'String'". *)
let string_of_ty : ty -> string = function
  | TInt -> "Int"
  | TBool -> "Bool"
  | TDouble -> "Double"
  | TString -> "String"

let equal (a : ty) (b : ty) : bool = a = b

(* The arithmetic types. `+ - * /` are defined on these (and `+` also on String);
   comparisons (`< > == …`) take these and yield `TBool`. *)
let is_numeric : ty -> bool = function
  | TInt | TDouble -> true
  | TBool | TString -> false

(* Map a type *name* as written in an annotation (`let x: Double = …`) to a type, or
   None if it isn't one of our known types (sema reports "cannot find type 'Foo'"). *)
let of_name : string -> ty option = function
  | "Int" -> Some TInt
  (* TODO(05): the three type names this concept adds. Everything else stays None, which is
     what makes sema say "cannot find type 'Foo' in scope". *)
  | _ -> None
