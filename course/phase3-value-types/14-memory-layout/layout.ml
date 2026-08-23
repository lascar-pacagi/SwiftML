(* Memory layout — concept 14 (skeleton). The dispatch + scalar/enum/optional sizes are given;
   you implement the STRUCT padding walk (TODO(14a)) and the field OFFSETS (TODO(14b)).

   The size, alignment, stride and field OFFSETS of a value type,
   the way it sits in memory. The rules are universal (natural alignment + padding); the
   numbers match swiftc EXACTLY for structs of scalars. (Enums/optionals use swiftml's naive
   {i64 tag, payload} model; swiftc packs the tag into the payload's spare bits — see the
   explainer's "how swiftc does it".) *)

(* round [n] up to the next multiple of [a] (a power-of-two alignment) *)
let round_up (n : int) (a : int) : int = if a <= 1 then n else (n + a - 1) / a * a

type info = { size : int; align : int }

(* size + alignment of a type. For a struct, lay the fields out in declaration order with
   padding so each lands on a multiple of its own alignment; the struct's size is the offset
   past the last field, its alignment the max of its fields'. *)
let rec info_of (m : Sil.modul) (t : Types.ty) : info =
  match t with
  | Types.TInt | Types.TDouble -> { size = 8; align = 8 }
  | Types.TBool -> { size = 1; align = 1 }
  | Types.TString -> { size = 8; align = 8 } (* a pointer *)
  | Types.TVoid -> { size = 0; align = 1 }
  | Types.TStruct n ->
      let sl = List.find (fun (s : Types.struct_layout) -> s.Types.sl_name = n) m.Sil.structs in
      struct_info m sl.Types.sl_fields
  | Types.TEnum n ->
      let el = List.find (fun (e : Types.enum_layout) -> e.Types.el_name = n) m.Sil.enums in
      { size = 8 * (1 + Types.max_payload el); align = 8 } (* tag word + payload words *)
  | Types.TOptional inner ->
      let i = info_of m inner in
      { size = 8 + i.size; align = 8 } (* { i64 tag, T } *)

and struct_info (m : Sil.modul) (fields : (string * Types.ty) list) : info =
  (* TODO(14a): the padding walk, in DECLARATION order — each field starts at the next offset
     that satisfies its own alignment, and the struct's alignment is the widest of them. Field
     order therefore changes the size; §2 works the examples. *)
  ignore (m, fields, round_up, info_of);
  failwith "TODO(14a-layout): the struct padding walk"


(* the stride is the size rounded up to the alignment — the distance between consecutive
   elements in an array (>= 1 even for an empty type) *)
let stride (i : info) : int = max 1 (round_up i.size (max 1 i.align))

(* the byte offset of each stored property — same padding walk, remembering each start *)
let field_offsets (m : Sil.modul) (fields : (string * Types.ty) list) : (string * int) list =
  (* TODO(14b): the same walk, keeping each field's start offset — what `MemoryLayout.offset(of:)`
     reports. *)
  ignore (m, fields);
  failwith "TODO(14b-layout): the field offsets"


(* `--emit-layout`: dump the layout of every scalar and every declared struct/enum *)
let emit_layout (m : Sil.modul) : string =
  let buf = Buffer.create 256 in
  let line name (i : info) = Buffer.add_string buf (Printf.sprintf "%s: size=%d stride=%d align=%d\n" name i.size (stride i) i.align) in
  List.iter (fun (n, t) -> line n (info_of m t)) [ ("Int", Types.TInt); ("Bool", Types.TBool); ("Double", Types.TDouble) ];
  List.iter
    (fun (sl : Types.struct_layout) ->
      line sl.Types.sl_name (info_of m (Types.TStruct sl.Types.sl_name));
      List.iter (fun (fn, o) -> Buffer.add_string buf (Printf.sprintf "  .%s offset=%d\n" fn o)) (field_offsets m sl.Types.sl_fields))
    m.Sil.structs;
  List.iter
    (fun (el : Types.enum_layout) -> line el.Types.el_name (info_of m (Types.TEnum el.Types.el_name)))
    m.Sil.enums;
  Buffer.contents buf
