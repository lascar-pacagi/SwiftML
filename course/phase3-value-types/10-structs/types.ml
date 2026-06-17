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
  | TStruct of string (* a value type — concept 10; the name keys the struct registry *)

(* the layout of a struct: its fields in declaration order (name, type). Built by sema/SILGen
   from the `struct` declaration and consulted for member access, init, and codegen. *)
type struct_layout = { sl_name : string; sl_fields : (string * ty) list }

let string_of_ty : ty -> string = function
  | TInt -> "Int"
  | TBool -> "Bool"
  | TDouble -> "Double"
  | TString -> "String"
  | TVoid -> "()"
  | TStruct n -> n

let equal (a : ty) (b : ty) : bool = a = b

let is_numeric : ty -> bool = function
  | TInt | TDouble -> true
  | TBool | TString | TVoid | TStruct _ -> false

(* field lookups on a layout *)
let field_index (sl : struct_layout) (f : string) : int option =
  let rec go i = function
    | (n, _) :: _ when n = f -> Some i
    | _ :: tl -> go (i + 1) tl
    | [] -> None
  in
  go 0 sl.sl_fields

let field_type (sl : struct_layout) (f : string) : ty option =
  List.assoc_opt f sl.sl_fields

let of_name : string -> ty option = function
  | "Int" -> Some TInt
  | "Bool" -> Some TBool
  | "Double" -> Some TDouble
  | "String" -> Some TString
  | "Void" -> Some TVoid
  | _ -> None
