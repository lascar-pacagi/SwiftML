(* Alcotest unit tests for concept-13 optionals: sema (contextual nil, wrapping, unwrap rules)
   and the emitted LLVM (the { tag, payload } type + the force-unwrap trap). *)

let errors (src : string) : string list =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Diagnostics.all d
  |> List.filter (fun (x : Diagnostics.t) -> x.Diagnostics.severity = Diagnostics.Error)
  |> List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message)

let llvm (src : string) : string =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
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
  accepted "let x: Int? = 5\nprint(x!)";            (* implicit wrap T -> T? *)
  accepted "let y: Int? = nil\nprint(y ?? 99)";     (* nil + coalescing *)
  accepted "let a: Int? = 5\nif let v = a { print(v) } else { print(0) }";
  accepted "let b: Int? = nil\nprint(b == nil)\nprint(b != nil)";
  accepted "func f(_ n: Int) -> Int? {\n  if n < 0 { return nil }\n  return n\n}\nprint(f(3) ?? -1)"

let test_rules () =
  has_error "let x = 5\nprint(x!)" "cannot force-unwrap a non-optional value of type 'Int'";
  has_error "let x = 5\nif let v = x { print(v) }"
    "initializer for conditional binding must have Optional type, not 'Int'";
  has_error "let x: Int = nil" "'nil' cannot be used with a non-optional type 'Int'";
  has_error "let x = 5\nprint(x ?? 0)" "left operand of '??' must be optional, found 'Int'"

let test_llvm_shape () =
  (* an optional is laid out as { tag, payload } and built with insertvalue *)
  ir_has "let x: Int? = 5\nprint(x!)" "{ i64, i64 }";
  ir_has "let x: Int? = 5\nprint(x!)" "insertvalue { i64, i64 }";
  (* force-unwrap emits a trap path *)
  ir_has "let x: Int? = nil\nprint(x!)" "@llvm.trap()"

let () =
  Alcotest.run "optionals"
    [
      ("accept", [ Alcotest.test_case "well-typed optional programs" `Quick test_accept ]);
      ("rules", [ Alcotest.test_case "nil/unwrap/coalesce rules" `Quick test_rules ]);
      ("llvm", [ Alcotest.test_case "optional layout + trap IR" `Quick test_llvm_shape ]);
    ]
