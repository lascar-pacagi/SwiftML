(* The type lattice — a *contract*. Concepts 05–06: Int/Bool/Double/String; 07: `TVoid`;
   10/11/13: structs, enums, optionals. Concept 21 adds `TProto` — a PROTOCOL used as a type
   (Swift's existential, `any P`): a value of unknown concrete type that is known to conform
   to P. Function *types* stay implicit (calls check against a signature table) until Phase 7. *)

type ty =
  | TInt
  | TBool
  | TDouble
  | TString
  | TVoid (* () — a value-less result *)
  | TStruct of string (* a value type — concept 10; the name keys the struct registry *)
  | TEnum of string (* a sum type — concept 11; the name keys the enum registry *)
  | TOptional of ty (* `T?` — concept 13; really `enum { none; some(T) }` (the tag is 0/1) *)
  | TProto of string (* `any P` — concept 21; an existential: (value, witness table) *)
  | TVar of string * string
    (* `T` inside `func f<T: P>` — concept 22: a TYPE PARAMETER (name, constraint protocol).
       Statically it's an opaque-but-CONSISTENT type; at runtime (unspecialized) a T value
       travels in the same (buffer, witness-table) representation as `any P`. *)

(* the layout of a struct: its fields in declaration order (name, type). *)
type struct_layout = { sl_name : string; sl_fields : (string * ty) list }

(* the layout of an enum: its cases in declaration order, each with its payload types (the
   case index is its tag). el_raw is true for a `: Int` raw-value enum (implicit raws = index). *)
type enum_layout = { el_name : string; el_cases : (string * ty list) list; el_raw : bool }

(* the layout of a protocol — concept 21: its requirements in declaration order. A requirement
   is a method signature (name, parameter types — self excluded — and return type); its index
   in this list is its WITNESS-TABLE SLOT. *)
type proto_layout = { pl_name : string; pl_reqs : (string * ty list * ty) list }

let rec string_of_ty : ty -> string = function
  | TInt -> "Int"
  | TBool -> "Bool"
  | TDouble -> "Double"
  | TString -> "String"
  | TVoid -> "()"
  | TStruct n -> n
  | TEnum n -> n
  | TOptional t -> string_of_ty t ^ "?"
  | TProto n -> "any " ^ n
  | TVar (n, _) -> n

let equal (a : ty) (b : ty) : bool = a = b

let is_numeric : ty -> bool = function
  | TInt | TDouble -> true
  | TBool | TString | TVoid | TStruct _ | TEnum _ | TOptional _ | TProto _ | TVar _ -> false

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

(* requirement lookups on a protocol layout *)
let req_index (pl : proto_layout) (m : string) : int option =
  let rec go i = function
    | (n, _, _) :: _ when n = m -> Some i
    | _ :: tl -> go (i + 1) tl
    | [] -> None
  in
  go 0 pl.pl_reqs

let req_sig (pl : proto_layout) (m : string) : (ty list * ty) option =
  List.find_map (fun (n, ps, r) -> if n = m then Some (ps, r) else None) pl.pl_reqs

let of_name : string -> ty option = function
  | "Int" -> Some TInt
  | "Bool" -> Some TBool
  | "Double" -> Some TDouble
  | "String" -> Some TString
  | "Void" -> Some TVoid
  | _ -> None
