(* Alcotest tests for concept 11, one group per TODO. Early groups stop at
   their own compiler stage; lowering groups inspect SIL or LLVM in process. *)

let lex_kinds (source : string) : string list =
  let diagnostics = Diagnostics.create () in
  Lexer.tokenize (Lexer.create source diagnostics)
  |> List.map (fun (token : Token.t) ->
         Token.string_of_kind token.Token.kind)

let parse (source : string) : Ast.program =
  let diagnostics = Diagnostics.create () in
  Parser.parse_program
    (Parser.create
       (Lexer.tokenize (Lexer.create source diagnostics))
       diagnostics)

let ast (source : string) : string = Ast.dump_program (parse source)

let front (source : string) : Ast.program * Diagnostics.sink =
  let diagnostics = Diagnostics.create () in
  let program =
    Parser.parse_program
      (Parser.create
         (Lexer.tokenize (Lexer.create source diagnostics))
         diagnostics)
  in
  Sema.check program diagnostics;
  (program, diagnostics)

let errors (source : string) : string list =
  let _, diagnostics = front source in
  Diagnostics.all diagnostics
  |> List.filter (fun (diagnostic : Diagnostics.t) ->
         diagnostic.Diagnostics.severity = Diagnostics.Error)
  |> List.map (fun (diagnostic : Diagnostics.t) ->
         diagnostic.Diagnostics.message)

let sil (source : string) : string =
  let program, _ = front source in
  Sil.string_of_module (Silgen.lower program)

let llvm (source : string) : string =
  let program, _ = front source in
  Irgen.emit_llvm (Silgen.lower program)

let color = "enum Color { case red, green, blue }\n"

let shape =
  "enum Shape {\n\
  \  case circle(Int)\n\
  \  case rect(Int, Int)\n\
  \  case dot\n\
   }\n"

let accepted source =
  Alcotest.(check (list string))
    (Printf.sprintf "accept %S" source)
    [] (errors source)

let has_error source message =
  Alcotest.(check bool)
    (Printf.sprintf "%S => %S" source message)
    true (List.mem message (errors source))

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec search index =
    index + needle_length <= haystack_length
    && (String.sub haystack index needle_length = needle
       || search (index + 1))
  in
  needle_length = 0 || search 0

let count haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec search index total =
    if index + needle_length > haystack_length then total
    else
      search (index + 1)
        (if String.sub haystack index needle_length = needle then total + 1
         else total)
  in
  if needle_length = 0 then 0 else search 0 0

let sil_has source needle =
  Alcotest.(check bool)
    (Printf.sprintf "sil has %S" needle)
    true (contains (sil source) needle)

let ir_has source needle =
  Alcotest.(check bool)
    (Printf.sprintf "ir has %S" needle)
    true (contains (llvm source) needle)

(* TODO(11a): keyword classification. *)

let test_enum_tokens () =
  Alcotest.(check (list string))
    "enum and case only"
    [ "enum"; "case"; "ident(enumerated)"; "ident(caseValue)"; "eof" ]
    (lex_kinds "enum case enumerated caseValue")

(* TODO(11b): declarations. *)

let test_parse_enum_decl () =
  Alcotest.(check string)
    "raw type, order, and payload types"
    "(enum Command :Int (stop move(Int,Bool) wait(Int)))"
    (ast
       "enum Command: Int { case stop; case move(Int, Bool); \
        case wait(Int) }")

(* TODO(11c): payload case expressions. *)

let test_parse_payload_case () =
  Alcotest.(check string)
    "method call then member"
    "(. (.call Shape circle 5) rawValue)"
    (ast "Shape.circle(5).rawValue")

(* TODO(11d): registry and layouts. *)

let test_enum_registry () =
  accepted
    "func identity(_ command: Command) -> Command { return command }\n\
     enum Command { case stop; case move(Int, Int) }";
  has_error "enum Flag { case value(Bool) }"
    "associated value type 'Bool' is not supported (only Int)";
  has_error "enum Flag: Bool { case off, on }"
    "raw type 'Bool' is not supported (only Int)";
  has_error "enum Bad { case value(Missing) }"
    "cannot find type 'Missing' in scope";
  has_error "enum A { case one }\nstruct A { var x: Int }"
    "invalid redeclaration of 'A'"

(* TODO(11e): construction typing. *)

let test_case_rules () =
  accepted
    "enum E { case empty; case pair(Int, Int) }\n\
     let a: E = E.empty\nlet b: E = E.pair(1, 2)";
  has_error "enum E { case empty }\nlet e = E.missing"
    "type 'E' has no member 'missing'";
  has_error "enum E { case pair(Int, Int) }\nlet e = E.pair(1)"
    "enum case 'E.pair' expects 2 associated value(s) but 1 given";
  has_error "enum E { case pair(Int, Int) }\nlet e = E.pair(1, true)"
    "cannot convert value of type 'Bool' to specified type 'Int'"

(* TODO(11f): raw values and equality. *)

let test_observation_rules () =
  accepted
    "enum Direction: Int { case north, south }\n\
     let value: Int = Direction.south.rawValue";
  accepted "enum C { case a, b }\nprint(C.a == C.b)";
  has_error "enum C { case a }\nprint(C.a.rawValue)"
    "value of type 'C' has no member 'rawValue'";
  has_error
    "enum E { case value(Int); case empty }\n\
     print(E.value(1) == E.value(1))"
    "type 'E' does not conform to protocol 'Equatable'"

(* TODO(11g): payload-free SIL construction. *)

let test_case_sil () =
  sil_has (color ^ "let c = Color.green") "enum #1 () $Color";
  sil_has (color ^ "let c = Color.blue") "enum #2 () $Color"

let test_tag_compare_sil () =
  let output = sil (color ^ "print(Color.red == Color.green)") in
  Alcotest.(check int) "two tag reads" 2 (count output "enum_tag");
  Alcotest.(check bool)
    "compared as Ints" true (contains output "binop \"==\"")

(* TODO(11h): payload SIL construction. *)

let test_payload_sil () =
  sil_has (shape ^ "let s = Shape.rect(3, 4)")
    "enum #1 (%0, %1) $Shape";
  sil_has (shape ^ "let s = Shape.circle(5)") "enum #0 (%0) $Shape"

let test_payload_order_sil () =
  let output =
    sil
      "enum K { case none; case one; case wide(Int, Int) }\n\
       let k = K.wide(7, 8)"
  in
  Alcotest.(check bool)
    "wide is #2" true (contains output "enum #2 (%0, %1) $K");
  Alcotest.(check int)
    "both operands are literals" 2 (count output "integer_literal")

(* TODO(11i): LLVM tagged unions. *)

let test_llvm_shape () =
  ir_has (color ^ "let c = Color.green") "%Color = type { i64 }";
  ir_has (color ^ "let c = Color.green")
    "insertvalue %Color undef, i64 1, 0";
  ir_has
    "enum Dir: Int { case north, south }\n\
     print(Dir.south.rawValue)"
    "extractvalue %Dir";
  ir_has (shape ^ "let s = Shape.rect(1, 2)")
    "%Shape = type { i64, i64, i64 }"

let () =
  Alcotest.run "enums"
    [
      ( "lexer-enums",
        [ Alcotest.test_case "enum and case keywords" `Quick test_enum_tokens ] );
      ( "parser-enum-decls",
        [ Alcotest.test_case "ordered cases and payloads" `Quick
            test_parse_enum_decl ] );
      ( "parser-enum-uses",
        [ Alcotest.test_case "payload call and chain" `Quick
            test_parse_payload_case ] );
      ( "sema-enum-decls",
        [ Alcotest.test_case "names first, then case layouts" `Quick
            test_enum_registry ] );
      ( "sema-enum-cases",
        [ Alcotest.test_case "lookup, arity, and types" `Quick
            test_case_rules ] );
      ( "sema-enum-observation",
        [ Alcotest.test_case "raw values and equality" `Quick
            test_observation_rules ] );
      ( "silgen-case",
        [
          Alcotest.test_case "Color.green is enum #1 ()" `Quick test_case_sil;
          Alcotest.test_case "== is two enum_tag reads" `Quick
            test_tag_compare_sil;
        ] );
      ( "silgen-payload",
        [
          Alcotest.test_case "rect(3,4) is enum #1 (a,b)" `Quick
            test_payload_sil;
          Alcotest.test_case "payload first, tag counts all" `Quick
            test_payload_order_sil;
        ] );
      ( "irgen-enums",
        [ Alcotest.test_case "tagged-union IR shape" `Quick test_llvm_shape ] );
    ]
