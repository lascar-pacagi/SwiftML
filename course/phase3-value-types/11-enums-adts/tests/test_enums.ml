(* Alcotest unit tests for concept 11, one group per stage so a hole is reachable on its own:
   sema (given: case typing, payload arity, raw values, the Equatable rule), the two silgen
   holes (a payload-free case, a payload-carrying case) checked on the SIL text, and the irgen
   hole (tagged-union types + insertvalue/extractvalue) on the LLVM text. *)

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

let color = "enum Color { case red, green, blue }\n"
let shape = "enum Shape {\n  case circle(Int)\n  case rect(Int, Int)\n  case dot\n}\n"
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
let ir_has src needle = Alcotest.(check bool) (Printf.sprintf "ir has %S" needle) true (contains (llvm src) needle)

(* --- sema (given) --- *)
let test_accept () =
  accepted (color ^ "let c = Color.red\nprint(c == Color.green)");
  accepted "enum Dir: Int { case north, south, east }\nprint(Dir.south.rawValue)";
  accepted (shape ^ "func use(_ s: Shape) -> Int { return 1 }\nprint(use(Shape.circle(5)))");
  accepted (color ^ "var c = Color.red\nc = Color.blue\nlet d: Color = c\nprint(d == Color.blue)")

let test_case_rules () =
  has_error "enum Color { case red, green }\nlet c = Color.blue" "type 'Color' has no member 'blue'";
  has_error "enum S { case pair(Int, Int) }\nlet s = S.pair(1)"
    "enum case 'S.pair' expects 2 associated value(s) but 1 given";
  has_error "enum S { case pair(Int, Int) }\nlet s = S.pair(1, true)"
    "cannot convert value of type 'Bool' to specified type 'Int'";
  (* a payload case named with no arguments: swiftc reads that as the case's constructor
     function, a value our subset has no type for, so we refuse it *)
  has_error "enum E { case a(Int) }\nlet e = E.a" "enum case 'E.a' requires arguments"

let test_equatable_and_raw () =
  (* an associated-value enum needs an Equatable conformance we do not synthesize: tag-only
     equality would call a(1) equal to a(2), so refusing is the faithful answer *)
  has_error "enum S {\n  case a(Int)\n  case b\n}\nprint(S.a(1) == S.a(1))"
    "type 'S' does not conform to protocol 'Equatable'";
  accepted "enum C { case a, b }\nprint(C.a == C.b)";
  (* rawValue only exists on a `: Int` raw-value enum *)
  has_error "enum Color { case red }\nprint(Color.red.rawValue)"
    "value of type 'Color' has no member 'rawValue'";
  (* and the back end has no way to print an enum, so sema refuses before IRGen sees it *)
  has_error (color ^ "print(Color.red)")
    "cannot print a value of type 'Color' (only Int, Double, Bool and String)"

(* --- silgen: TODO(11) a payload-free case --- *)
let test_case_sil () =
  sil_has (color ^ "let c = Color.green") "enum #1 () $Color";
  sil_has (color ^ "let c = Color.blue") "enum #2 () $Color"

let test_tag_compare_sil () =
  (* `==` on an enum is two enum_tag reads and an integer compare *)
  let s = sil (color ^ "print(Color.red == Color.green)") in
  Alcotest.(check int) "two tag reads" 2 (count s "enum_tag");
  Alcotest.(check bool) "compared as Ints" true (contains s "binop \"==\"")

(* --- silgen: TODO(11) a payload-carrying case --- *)
let test_payload_sil () =
  sil_has (shape ^ "let s = Shape.rect(3, 4)") "enum #1 (%0, %1) $Shape";
  sil_has (shape ^ "let s = Shape.circle(5)") "enum #0 (%0) $Shape"

let test_payload_order_sil () =
  (* the payload is evaluated BEFORE the case is built, and the tag counts every case *)
  let s = sil ("enum K {\n  case none\n  case one\n  case wide(Int, Int)\n}\nlet k = K.wide(7, 8)") in
  Alcotest.(check bool) "wide is #2" true (contains s "enum #2 (%0, %1) $K");
  Alcotest.(check int) "both operands are literals" 2 (count s "integer_literal")

(* --- irgen: TODO(11) the tagged union --- *)
let test_llvm_shape () =
  ir_has (color ^ "let c = Color.green") "%Color = type { i64 }";
  ir_has (color ^ "let c = Color.green") "insertvalue %Color undef, i64 1, 0";
  ir_has "enum Dir: Int { case north, south }\nprint(Dir.south.rawValue)" "extractvalue %Dir";
  (* a tagged union sizes its payload to the widest case *)
  ir_has (shape ^ "let s = Shape.rect(1, 2)") "%Shape = type { i64, i64, i64 }";
  ir_has (shape ^ "let s = Shape.rect(1, 2)") "insertvalue %Shape %t2, i64 2, 2"

let () =
  Alcotest.run "enums"
    [
      ( "sema-enums",
        [
          Alcotest.test_case "well-typed enum programs" `Quick test_accept;
          Alcotest.test_case "case lookup + payload arity" `Quick test_case_rules;
          Alcotest.test_case "Equatable, rawValue, print" `Quick test_equatable_and_raw;
        ] );
      ( "silgen-case",
        [
          Alcotest.test_case "Color.green is enum #1 ()" `Quick test_case_sil;
          Alcotest.test_case "== is two enum_tag reads" `Quick test_tag_compare_sil;
        ] );
      ( "silgen-payload",
        [
          Alcotest.test_case "rect(3,4) is enum #1 (a,b)" `Quick test_payload_sil;
          Alcotest.test_case "payload first, tag counts all" `Quick test_payload_order_sil;
        ] );
      ("irgen-enums", [ Alcotest.test_case "tagged-union IR shape" `Quick test_llvm_shape ]);
    ]
