(* Alcotest unit tests for concept-11 enums: sema (case typing, raw values, Equatable rules)
   and the emitted LLVM (tagged-union types + insertvalue/extractvalue). *)

let errors (src : string) : string list =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  Diagnostics.all d
  |> List.filter (fun (x : Diagnostics.t) -> x.Diagnostics.severity = Diagnostics.Error)
  |> List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message)

let llvm (src : string) : string =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  Irgen.emit_llvm (Silgen.lower p)

let accepted src = Alcotest.(check (list string)) (Printf.sprintf "accept %S" src) [] (errors src)
let has_error src msg = Alcotest.(check bool) (Printf.sprintf "%S => %S" src msg) true (List.mem msg (errors src))
let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  m = 0 || go 0
let ir_has src needle = Alcotest.(check bool) (Printf.sprintf "ir has %S" needle) true (contains (llvm src) needle)

let test_accept () =
  accepted "enum Color { case red, green, blue }\nlet c = Color.red\nprint(c == Color.green)";
  accepted "enum Dir: Int { case north, south, east }\nprint(Dir.south.rawValue)";
  accepted "enum Shape {\n  case circle(Int)\n  case dot\n}\nlet s = Shape.circle(5)"

let test_case_rules () =
  has_error "enum Color { case red, green }\nlet c = Color.blue" "type 'Color' has no case 'blue'";
  has_error "enum S { case pair(Int, Int) }\nlet s = S.pair(1)"
    "enum case 'S.pair' expects 2 associated value(s) but 1 given";
  (* a no-payload case used like a function, or vice versa *)
  has_error "enum E { case a(Int) }\nlet e = E.a" "enum case 'E.a' requires arguments"

let test_equatable_and_raw () =
  (* associated-value enums need an explicit Equatable conformance (which we defer), so == is rejected *)
  has_error "enum S {\n  case a(Int)\n  case b\n}\nprint(S.a(1) == S.a(1))"
    "type 'S' does not conform to protocol 'Equatable'";
  (* rawValue only exists on a `: Int` raw-value enum *)
  has_error "enum Color { case red }\nprint(Color.red.rawValue)"
    "value of type 'Color' has no member 'rawValue'"

let test_llvm_shape () =
  ir_has "enum Color { case red, green, blue }\nlet c = Color.green\nprint(c == Color.green)"
    "%Color = type { i64 }";
  ir_has "enum Color { case red, green }\nlet c = Color.green\nprint(c == Color.red)" "insertvalue %Color";
  ir_has "enum Color { case red, green }\nlet c = Color.green\nprint(c == Color.red)" "extractvalue %Color";
  (* a tagged union sizes its payload to the widest case *)
  ir_has "enum Shape {\n  case circle(Int)\n  case rect(Int, Int)\n}\nlet s = Shape.rect(1, 2)"
    "%Shape = type { i64, i64, i64 }"

let () =
  Alcotest.run "enums"
    [
      ("accept", [ Alcotest.test_case "well-typed enum programs" `Quick test_accept ]);
      ("cases", [ Alcotest.test_case "case lookup + payload arity" `Quick test_case_rules ]);
      ("rules", [ Alcotest.test_case "Equatable + rawValue rules" `Quick test_equatable_and_raw ]);
      ("llvm", [ Alcotest.test_case "tagged-union IR shape" `Quick test_llvm_shape ]);
    ]
