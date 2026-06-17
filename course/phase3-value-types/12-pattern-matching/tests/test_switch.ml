(* Alcotest unit tests for concept-12 pattern matching: sema (exhaustiveness, pattern typing)
   and the lowered SIL (tag dispatch + payload binding). *)

let errors (src : string) : string list =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  Diagnostics.all d
  |> List.filter (fun (x : Diagnostics.t) -> x.Diagnostics.severity = Diagnostics.Error)
  |> List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message)

let sil (src : string) : string =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
  Sema.check p d;
  Sil.string_of_module (Silgen.lower p)

let accepted src = Alcotest.(check (list string)) (Printf.sprintf "accept %S" src) [] (errors src)
let has_error src msg = Alcotest.(check bool) (Printf.sprintf "%S => %S" src msg) true (List.mem msg (errors src))
let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  m = 0 || go 0

let shape = "enum Shape {\n  case circle(Int)\n  case rect(Int, Int)\n  case dot\n}\n"

let test_accept () =
  accepted (shape ^ "let s = Shape.dot\nswitch s {\ncase .circle(let r): print(r)\ncase .rect(let w, let h): print(w * h)\ncase .dot: print(0)\n}");
  (* a default makes a partial enum switch exhaustive *)
  accepted (shape ^ "let s = Shape.dot\nswitch s {\ncase .dot: print(1)\ndefault: print(0)\n}");
  accepted "let n = 2\nswitch n {\ncase 0: print(0)\ncase 1: print(1)\ndefault: print(9)\n}"

let test_exhaustiveness () =
  has_error (shape ^ "let s = Shape.dot\nswitch s {\ncase .dot: print(0)\n}") "switch must be exhaustive";
  has_error "let n = 1\nswitch n {\ncase 0: print(0)\ncase 1: print(1)\n}" "switch must be exhaustive"

let test_pattern_rules () =
  has_error (shape ^ "let s = Shape.dot\nswitch s {\ncase .circle(let r): print(r)\ncase .square: print(0)\ndefault: print(1)\n}")
    "type 'Shape' has no case 'square'";
  has_error (shape ^ "let s = Shape.dot\nswitch s {\ncase .rect(let w): print(w)\ndefault: print(0)\n}")
    "pattern '.rect' binds 1 value(s) but case 'rect' has 2 associated value(s)"

let test_sil_shape () =
  let s = sil (shape ^ "let s = Shape.circle(5)\nswitch s {\ncase .circle(let r): print(r)\ncase .rect(let w, let h): print(w)\ncase .dot: print(0)\n}") in
  Alcotest.(check bool) "reads the tag (enum_tag)" true (contains s "enum_tag");
  Alcotest.(check bool) "binds payload (enum_payload)" true (contains s "enum_payload");
  Alcotest.(check bool) "dispatches (cond_br)" true (contains s "cond_br")

let () =
  Alcotest.run "switch"
    [
      ("accept", [ Alcotest.test_case "well-typed switches" `Quick test_accept ]);
      ("exhaustive", [ Alcotest.test_case "exhaustiveness diagnostics" `Quick test_exhaustiveness ]);
      ("patterns", [ Alcotest.test_case "case + binding rules" `Quick test_pattern_rules ]);
      ("sil", [ Alcotest.test_case "dispatch + binding SIL" `Quick test_sil_shape ]);
    ]
