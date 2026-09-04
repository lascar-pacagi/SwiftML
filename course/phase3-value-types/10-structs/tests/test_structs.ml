(* Alcotest unit tests for concept 10, one group per stage so a hole shows on its own:
   sema (given: member typing, init, value-type rules), the two silgen holes (read =
   struct_extract, write = struct_element_addr) checked on the SIL text, and the irgen hole
   (aggregate types + insertvalue/extractvalue/getelementptr) on the LLVM text. *)

let front (src : string) : Ast.program * Diagnostics.sink =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  (p, d)

let errors (src : string) : string list =
  let _, d = front src in
  Diagnostics.all d
  |> List.filter (fun (x : Diagnostics.t) -> x.Diagnostics.severity = Diagnostics.Error)
  |> List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message)

let sil (src : string) : string =
  let p, _ = front src in
  Sil.string_of_module (Silgen.lower p)

let llvm (src : string) : string =
  let p, _ = front src in
  Irgen.emit_llvm (Silgen.lower p)

let point = "struct Point {\n  var x: Int\n  var y: Int\n}\n"
let line = point ^ "struct Line {\n  var a: Point\n  var b: Point\n}\n"
let accepted src = Alcotest.(check (list string)) (Printf.sprintf "accept %S" src) [] (errors src)
let has_error src msg = Alcotest.(check bool) (Printf.sprintf "%S => %S" src msg) true (List.mem msg (errors src))

let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  m = 0 || go 0

let count hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i acc = if i + m > n then acc else go (i + 1) (if String.sub hay i m = needle then acc + 1 else acc) in
  if m = 0 then 0 else go 0 0

let sil_has src needle = Alcotest.(check bool) (Printf.sprintf "sil has %S" needle) true (contains (sil src) needle)
let sil_lacks src needle = Alcotest.(check bool) (Printf.sprintf "sil lacks %S" needle) false (contains (sil src) needle)
let ir_has src needle = Alcotest.(check bool) (Printf.sprintf "ir has %S" needle) true (contains (llvm src) needle)

(* --- sema (given) --- *)
let test_accept () =
  accepted (point ^ "let p = Point(x: 3, y: 4)\nprint(p.x)");
  accepted (point ^ "var p = Point(x: 1, y: 2)\np.x = 9\nprint(p.x)");
  accepted (point ^ "func sum(_ p: Point) -> Int { return p.x + p.y }\nprint(sum(Point(x: 1, y: 2)))");
  accepted (line ^ "let l = Line(a: Point(x: 0, y: 0), b: Point(x: 7, y: 9))\nprint(l.b.x)");
  accepted ("struct S {\n  let x: Int\n  var y: Int\n}\nvar s = S(x: 1, y: 2)\ns.y = 3\nprint(s.x)")

let test_init_rules () =
  has_error (point ^ "let p = Point(x: \"s\", y: 2)") "cannot convert value of type 'String' to specified type 'Int'";
  has_error (point ^ "let p = Point(1, 2)") "missing argument label 'x:' in call";
  has_error (point ^ "let p = Point(z: 1, y: 2)") "incorrect argument label in call (have 'z:', expected 'x:')";
  has_error (point ^ "let p = Point(x: 1)") "'Point' initializer expects 2 argument(s) but 1 given";
  has_error "let p = Nope(x: 1)" "cannot find 'Nope' in scope"

let test_member_rules () =
  has_error (point ^ "let p = Point(x: 1, y: 2)\nprint(p.z)") "value of type 'Point' has no member 'z'";
  has_error "let n = 3\nprint(n.x)" "value of type 'Int' has no member 'x'";
  (* value semantics is enforced through `let`: a let-bound struct's fields can't be assigned *)
  has_error (point ^ "let p = Point(x: 1, y: 2)\np.x = 5") "cannot assign to property: 'p' is a 'let' constant";
  (* and a `let` FIELD is immutable through any binding, `var` included *)
  has_error "struct S {\n  let x: Int\n  var y: Int\n}\nvar s = S(x: 1, y: 2)\ns.x = 2"
    "cannot assign to property: 'x' is a 'let' constant"

let test_backend_guards () =
  (* two programs swiftc treats differently from us, refused in sema so the back end never
     sees an aggregate it cannot compare or print (each used to crash the compiler) *)
  has_error (point ^ "let p = Point(x: 1, y: 2)\nprint(p == p)") "binary operator '==' cannot be applied to two 'Point' operands";
  has_error (point ^ "let p = Point(x: 1, y: 2)\nprint(p)") "cannot print a value of type 'Point' (only Int, Double, Bool and String)"

(* --- silgen: TODO(10) member read --- *)
let test_read_sil () =
  let src = point ^ "let p = Point(x: 3, y: 4)\nprint(p.y)" in
  sil_has src "struct_extract";
  sil_has src ", #1 $Int";
  sil_lacks src "struct_element_addr"

let test_read_nested_sil () =
  let s = sil (line ^ "let l = Line(a: Point(x: 0, y: 0), b: Point(x: 7, y: 9))\nprint(l.b.x)") in
  Alcotest.(check int) "two extracts for l.b.x" 2 (count s "struct_extract");
  Alcotest.(check bool) "inner Point first (#1 $Point)" true (contains s ", #1 $Point")

(* --- silgen: TODO(10) member write --- *)
let test_write_sil () =
  let src = point ^ "var p = Point(x: 1, y: 2)\np.x = 9" in
  sil_has src "struct_element_addr %3, #0";
  sil_has src "store %5 to %6";
  sil_lacks src "struct_extract"

let test_write_own_slot () =
  (* value semantics in the SIL: q's write addresses q's slot, and p's slot is never addressed *)
  let s = sil (point ^ "var p = Point(x: 1, y: 2)\nvar q = p\nq.x = 99") in
  Alcotest.(check int) "one field address taken" 1 (count s "struct_element_addr");
  Alcotest.(check bool) "it is q's slot (%6), not p's (%3)" true (contains s "struct_element_addr %6, #0")

(* --- irgen: TODO(10) aggregates --- *)
let test_llvm_shape () =
  ir_has (point ^ "let p = Point(x: 1, y: 2)") "%Point = type { i64, i64 }";
  ir_has (point ^ "let p = Point(x: 1, y: 2)") "insertvalue %Point undef, i64";
  ir_has (point ^ "var p = Point(x: 1, y: 2)\nprint(p.x)") "extractvalue %Point";
  ir_has (point ^ "var p = Point(x: 1, y: 2)\np.x = 9\nprint(p.x)") "getelementptr %Point";
  ir_has (line ^ "let l = Line(a: Point(x: 0, y: 0), b: Point(x: 7, y: 9))") "%Line = type { %Point, %Point }"

let () =
  Alcotest.run "structs"
    [
      ( "sema-structs",
        [
          Alcotest.test_case "well-typed struct programs" `Quick test_accept;
          Alcotest.test_case "memberwise init rules" `Quick test_init_rules;
          Alcotest.test_case "member access + let rules" `Quick test_member_rules;
          Alcotest.test_case "== and print refused up front" `Quick test_backend_guards;
        ] );
      ( "silgen-member-read",
        [
          Alcotest.test_case "p.y is struct_extract #1" `Quick test_read_sil;
          Alcotest.test_case "l.b.x is two extracts" `Quick test_read_nested_sil;
        ] );
      ( "silgen-member-write",
        [
          Alcotest.test_case "p.x = 9 is element_addr #0" `Quick test_write_sil;
          Alcotest.test_case "q.x = 99 addresses q's slot" `Quick test_write_own_slot;
        ] );
      ("irgen-structs", [ Alcotest.test_case "aggregate IR shape" `Quick test_llvm_shape ]);
    ]
