(* Alcotest unit tests for concept 14, one group per hole so each is reachable on its own:
   layout-padding calls `Layout.struct_info` (TODO(14a)) and layout-offsets calls
   `Layout.field_offsets` (TODO(14b)) directly, which the `--emit-layout` cram files cannot do
   — the driver prints sizes and offsets together, so those two go green together. *)

let lower src =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Silgen.lower p

let info src ty = Layout.info_of (lower src) ty

let fields src name =
  let m = lower src in
  let sl = List.find (fun (s : Types.struct_layout) -> s.Types.sl_name = name) m.Sil.structs in
  (m, sl.Types.sl_fields)

let offsets src name =
  let m, fs = fields src name in
  Layout.field_offsets m fs

(* --- given: the scalar base cases and the stride rule --- *)
let test_scalars () =
  let m = lower "struct X {\n  var x: Int\n}" in
  Alcotest.(check int) "Int size" 8 (Layout.info_of m Types.TInt).Layout.size;
  Alcotest.(check int) "Int align" 8 (Layout.info_of m Types.TInt).Layout.align;
  Alcotest.(check int) "Double size" 8 (Layout.info_of m Types.TDouble).Layout.size;
  Alcotest.(check int) "Bool size" 1 (Layout.info_of m Types.TBool).Layout.size;
  Alcotest.(check int) "Bool align" 1 (Layout.info_of m Types.TBool).Layout.align;
  Alcotest.(check int) "Bool stride" 1 (Layout.stride (Layout.info_of m Types.TBool))

(* --- TODO(14a): the padding walk --- *)
let test_padding () =
  (* {Int; Bool} = size 9 (no trailing pad in the SIZE) but stride 16 (size rounded to align) *)
  let i = info "struct A {\n  var i: Int\n  var b: Bool\n}" (Types.TStruct "A") in
  Alcotest.(check int) "size" 9 i.Layout.size;
  Alcotest.(check int) "align" 8 i.Layout.align;
  Alcotest.(check int) "stride" 16 (Layout.stride i);
  (* the same two fields the other way round: the Bool is padded so the Int lands on 8 *)
  let j = info "struct B {\n  var b: Bool\n  var i: Int\n}" (Types.TStruct "B") in
  Alcotest.(check int) "padded size" 16 j.Layout.size;
  (* Bools align to 1, so a run of them costs one byte each and the struct aligns to 1 *)
  let k = info "struct F {\n  var a: Bool\n  var b: Bool\n  var c: Bool\n}" (Types.TStruct "F") in
  Alcotest.(check int) "three Bools" 3 k.Layout.size;
  Alcotest.(check int) "align 1" 1 k.Layout.align;
  Alcotest.(check int) "stride 3" 3 (Layout.stride k)

let test_padding_nested () =
  (* a struct field brings its OWN alignment and size into the walk *)
  let src = "struct I {\n  var a: Bool\n  var b: Int\n}\nstruct O {\n  var flag: Bool\n  var inner: I\n}" in
  let i = info src (Types.TStruct "I") and o = info src (Types.TStruct "O") in
  Alcotest.(check int) "inner size" 16 i.Layout.size;
  Alcotest.(check int) "outer size" 24 o.Layout.size;
  Alcotest.(check int) "outer align" 8 o.Layout.align

(* --- TODO(14b): the field offsets --- *)
let test_offsets () =
  Alcotest.(check (list (pair string int)))
    "padded" [ ("b", 0); ("i", 8) ] (offsets "struct M {\n  var b: Bool\n  var i: Int\n}" "M");
  Alcotest.(check (list (pair string int)))
    "packed" [ ("i", 0); ("b", 8) ] (offsets "struct N {\n  var i: Int\n  var b: Bool\n}" "N");
  Alcotest.(check (list (pair string int)))
    "consecutive Bools" [ ("a", 0); ("b", 1); ("c", 8) ]
    (offsets "struct T {\n  var a: Bool\n  var b: Bool\n  var c: Int\n}" "T")

let test_offsets_nested () =
  (* a nested struct takes one slot, at its own alignment — .inner is at 8, not at 1 *)
  let src = "struct I {\n  var a: Bool\n  var b: Int\n}\nstruct O {\n  var flag: Bool\n  var inner: I\n}" in
  Alcotest.(check (list (pair string int))) "outer" [ ("flag", 0); ("inner", 8) ] (offsets src "O");
  (* the last offset plus that field's size, rounded to the struct's alignment, is the stride *)
  let o = info src (Types.TStruct "O") in
  Alcotest.(check int) "offset + size = size" 24 o.Layout.size

let () =
  Alcotest.run "layout"
    [
      ("layout-scalars", [ Alcotest.test_case "scalar sizes and strides" `Quick test_scalars ]);
      ( "layout-padding",
        [
          Alcotest.test_case "field order changes size" `Quick test_padding;
          Alcotest.test_case "a struct field brings align" `Quick test_padding_nested;
        ] );
      ( "layout-offsets",
        [
          Alcotest.test_case "offsets show the padding" `Quick test_offsets;
          Alcotest.test_case "a nested struct is one slot" `Quick test_offsets_nested;
        ] );
    ]
