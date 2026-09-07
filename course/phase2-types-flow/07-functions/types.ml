(* The Phase-2 type lattice — a *contract*. Concepts 05–06 had Int/Bool/Double/String;
   concept 07 adds `TVoid` (Swift's `()`), the result type of a function with no `-> T`
   (and of print). Function *types* themselves stay implicit — calls are checked against a
   signature table in sema, not represented as a first-class type (that's Phase 7). *)

type ty =
  | TInt
  | TBool
  | TDouble
  | TString
  | TVoid (* () — a value-less result *)

(* NOT inverses, and `TVoid` is where that shows. `string_of_ty` produces what a DIAGNOSTIC says;
   `of_name` reads what SOURCE writes — and Swift spells those differently. `Void` is a standard
   library typealias for the empty tuple (`public typealias Void = ()`), so you write `Void` but
   swiftc prints the canonical `()`: "cannot convert value of type '()' to specified type 'Int'",
   which §2's table pins character for character.

   So `of_name (string_of_ty TVoid)` is `None`. A function with no `-> T` returns `TVoid`
   directly — there is no written name to resolve, and asking for one by its printed form is how
   you end up reporting `cannot find type '()' in scope`.

   (Divergence: swiftc also accepts `-> ()` as a written type. Our `parse_ident_ty` reads an
   identifier and `()` is two punctuation tokens, so the subset cannot spell it either way.) *)

let string_of_ty : ty -> string = function
  | TInt -> "Int"
  | TBool -> "Bool"
  | TDouble -> "Double"
  | TString -> "String"
  | TVoid -> "()"

let equal (a : ty) (b : ty) : bool = a = b

let is_numeric : ty -> bool = function
  | TInt | TDouble -> true
  | TBool | TString | TVoid -> false

let of_name : string -> ty option = function
  | "Int" -> Some TInt
  | "Bool" -> Some TBool
  | "Double" -> Some TDouble
  | "String" -> Some TString
  | "Void" -> Some TVoid
  | _ -> None
