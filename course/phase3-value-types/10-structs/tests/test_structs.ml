(* Alcotest unit tests for concept-10 structs: sema (member typing, init, value-type rules)
   and the emitted LLVM (aggregate types + insertvalue/extractvalue/getelementptr). *)

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

let point = "struct Point {\n  var x: Int\n  var y: Int\n}\n"
let accepted src = Alcotest.(check (list string)) (Printf.sprintf "accept %S" src) [] (errors src)
let has_error src msg = Alcotest.(check bool) (Printf.sprintf "%S => %S" src msg) true (List.mem msg (errors src))
let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  m = 0 || go 0
let ir_has src needle = Alcotest.(check bool) (Printf.sprintf "ir has %S" needle) true (contains (llvm src) needle)

let test_accept () =
  accepted (point ^ "let p = Point(x: 3, y: 4)\nprint(p.x)");
  accepted (point ^ "var p = Point(x: 1, y: 2)\np.x = 9\nprint(p.x)");
  accepted (point ^ "func sum(_ p: Point) -> Int { return p.x + p.y }\nprint(sum(Point(x: 1, y: 2)))")

let test_init_rules () =
  has_error (point ^ "let p = Point(x: \"s\", y: 2)") "cannot convert value of type 'String' to specified type 'Int'";
  has_error (point ^ "let p = Point(1, 2)") "missing argument label 'x:' in call";
  has_error (point ^ "let p = Point(z: 1, y: 2)") "incorrect argument label in call (have 'z:', expected 'x:')";
  has_error (point ^ "let p = Point(x: 1)") "'Point' initializer expects 2 argument(s) but 1 given"

let test_member_rules () =
  has_error (point ^ "let p = Point(x: 1, y: 2)\nprint(p.z)") "value of type 'Point' has no member 'z'";
  (* value semantics is enforced through `let`: a let-bound struct's fields can't be assigned *)
  has_error (point ^ "let p = Point(x: 1, y: 2)\np.x = 5") "cannot assign to property 'x': 'p' is a 'let' constant"

let test_llvm_shape () =
  ir_has (point ^ "var p = Point(x: 1, y: 2)\nprint(p.x)") "%Point = type { i64, i64 }";
  ir_has (point ^ "var p = Point(x: 1, y: 2)\nprint(p.x)") "insertvalue %Point";
  ir_has (point ^ "var p = Point(x: 1, y: 2)\nprint(p.x)") "extractvalue %Point";
  ir_has (point ^ "var p = Point(x: 1, y: 2)\np.x = 9\nprint(p.x)") "getelementptr %Point"

let () =
  Alcotest.run "structs"
    [
      ("accept", [ Alcotest.test_case "well-typed struct programs" `Quick test_accept ]);
      ("init", [ Alcotest.test_case "memberwise init rules" `Quick test_init_rules ]);
      ("members", [ Alcotest.test_case "member access + value-type rules" `Quick test_member_rules ]);
      ("llvm", [ Alcotest.test_case "aggregate IR shape" `Quick test_llvm_shape ]);
    ]
