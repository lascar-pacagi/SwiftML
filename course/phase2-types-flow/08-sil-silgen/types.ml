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
