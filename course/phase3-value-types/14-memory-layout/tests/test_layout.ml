(* Alcotest unit tests for concept-14: the layout computation matches swiftc's MemoryLayout. *)
let lower src =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d; Silgen.lower p
let info src ty = Layout.info_of (lower src) ty
let test_scalars () =
  let m = lower "struct X { var x: Int }" in
  Alcotest.(check int) "Int size" 8 (Layout.info_of m Types.TInt).Layout.size;
  Alcotest.(check int) "Bool size" 1 (Layout.info_of m Types.TBool).Layout.size;
  Alcotest.(check int) "Bool stride" 1 (Layout.stride (Layout.info_of m Types.TBool))
let test_padding () =
  (* {Int; Bool} = size 9 (no trailing pad in size); stride 16 (rounded to align) *)
  let i = info "struct A { var i: Int; var b: Bool }" (Types.TStruct "A") in
  Alcotest.(check int) "size" 9 i.Layout.size;
  Alcotest.(check int) "align" 8 i.Layout.align;
  Alcotest.(check int) "stride" 16 (Layout.stride i);
  (* {Bool; Int} = size 16 (Bool padded up so Int lands at 8) *)
  let j = info "struct B { var b: Bool; var i: Int }" (Types.TStruct "B") in
  Alcotest.(check int) "padded size" 16 j.Layout.size
let test_offsets () =
  let m = lower "struct M { var b: Bool; var i: Int }" in
  let sl = List.find (fun (s:Types.struct_layout) -> s.Types.sl_name = "M") m.Sil.structs in
  Alcotest.(check (list (pair string int))) "offsets" [ ("b", 0); ("i", 8) ] (Layout.field_offsets m sl.Types.sl_fields)
let test_nested () =
  let i = info "struct I { var a: Bool; var b: Int }\nstruct O { var flag: Bool; var inner: I }" (Types.TStruct "O") in
  Alcotest.(check int) "nested struct size" 24 i.Layout.size
let () = Alcotest.run "layout" [
  ("scalars", [ Alcotest.test_case "scalar sizes" `Quick test_scalars ]);
  ("padding", [ Alcotest.test_case "field padding" `Quick test_padding ]);
  ("offsets", [ Alcotest.test_case "field offsets" `Quick test_offsets ]);
  ("nested", [ Alcotest.test_case "composition" `Quick test_nested ]); ]
