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
  | TStruct name -> name

let equal (left : ty) (right : ty) : bool = left = right

let is_numeric : ty -> bool = function
  | TInt | TDouble -> true
  | TBool | TString | TVoid | TStruct _ -> false

(* field lookups on a layout *)
let field_index (layout : struct_layout) (field_name : string) : int option =
  let rec search index = function
    | (name, _) :: _ when name = field_name -> Some index
    | _ :: remaining_fields -> search (index + 1) remaining_fields
    | [] -> None
  in
  search 0 layout.sl_fields

let field_type (layout : struct_layout) (field_name : string) : ty option =
  List.assoc_opt field_name layout.sl_fields

let of_name : string -> ty option = function
  | "Int" -> Some TInt
  | "Bool" -> Some TBool
  | "Double" -> Some TDouble
  | "String" -> Some TString
  | "Void" -> Some TVoid
  | _ -> None
