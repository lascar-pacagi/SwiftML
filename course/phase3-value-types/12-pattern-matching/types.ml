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
  | TEnum of string (* a sum type — concept 11; the name keys the enum registry *)

(* the layout of a struct: its fields in declaration order (name, type). *)
type struct_layout = { sl_name : string; sl_fields : (string * ty) list }

(* the layout of an enum: its cases in declaration order, each with its payload types (the
   case index is its tag). el_raw is true for a `: Int` raw-value enum (implicit raws = index). *)
type enum_layout = { el_name : string; el_cases : (string * ty list) list; el_raw : bool }

let string_of_ty : ty -> string = function
  | TInt -> "Int"
  | TBool -> "Bool"
  | TDouble -> "Double"
  | TString -> "String"
  | TVoid -> "()"
  | TStruct n -> n
  | TEnum n -> n

let equal (a : ty) (b : ty) : bool = a = b

let is_numeric : ty -> bool = function
  | TInt | TDouble -> true
  | TBool | TString | TVoid | TStruct _ | TEnum _ -> false

(* enum helpers: a case's tag (index) and its payload types *)
let case_index (el : enum_layout) (c : string) : int option =
  let rec go i = function
    | (n, _) :: _ when n = c -> Some i
    | _ :: tl -> go (i + 1) tl
    | [] -> None
  in
  go 0 el.el_cases

let case_payload (el : enum_layout) (c : string) : ty list option =
  Option.map snd (List.find_opt (fun (n, _) -> n = c) el.el_cases)

let max_payload (el : enum_layout) : int =
  List.fold_left (fun m (_, tys) -> max m (List.length tys)) 0 el.el_cases

let has_payload (el : enum_layout) : bool = max_payload el > 0

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
