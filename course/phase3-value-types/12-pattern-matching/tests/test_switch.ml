(* Alcotest unit tests for concept 12, one group per hole so each is reachable on its own:
   sema-switch (given: pattern typing, binding scope), sema-exhaustive (the TODO(12-sema)
   hole), and silgen-switch (the TODO(12) dispatch chain) read off the SIL text. *)

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

let shape = "enum Shape {\n  case circle(Int)\n  case rect(Int, Int)\n  case dot\n}\n"
let full = shape ^ "let s = Shape.circle(5)\nswitch s {\ncase .circle(let r): print(r)\ncase .rect(let w, let h): print(w * h)\ncase .dot: print(0)\n}"

(* --- sema (given): pattern typing --- *)
let test_accept () =
  accepted full;
  (* a default makes a partial enum switch exhaustive *)
  accepted (shape ^ "let s = Shape.dot\nswitch s {\ncase .dot: print(1)\ndefault: print(0)\n}");
  accepted "let n = 2\nswitch n {\ncase 0: print(0)\ncase 1: print(1)\ndefault: print(9)\n}"

let test_pattern_rules () =
  has_error (shape ^ "let s = Shape.dot\nswitch s {\ncase .circle(let r): print(r)\ncase .square: print(0)\ndefault: print(1)\n}")
    "type 'Shape' has no member 'square'";
  (* swiftc accepts this one, reading `.rect(let w)` as the whole tuple; we have no tuple *)
  has_error (shape ^ "let s = Shape.dot\nswitch s {\ncase .rect(let w): print(w)\ndefault: print(0)\n}")
    "pattern '.rect' binds 1 value(s) but case 'rect' has 2 associated value(s)";
  has_error "enum E { case a, b }\nlet e = E.a\nswitch e {\ncase 1: print(1)\ndefault: print(0)\n}"
    "expression pattern of type 'Int' cannot match values of type 'E'";
  has_error "let b = true\nswitch b {\ncase 1: print(1)\ndefault: print(0)\n}"
    "cannot 'switch' over a value of type 'Bool'"

let test_binding_scope () =
  (* a binding lives in ITS arm only, and carries the payload's declared type *)
  has_error (shape ^ "let s = Shape.dot\nswitch s {\ncase .circle(let r): print(r)\ncase .dot: print(r)\n}")
    "cannot find 'r' in scope";
  has_error (shape ^ "let s = Shape.dot\nswitch s {\ncase .circle(let r): let b: Bool = r\ndefault: print(0)\n}")
    "cannot convert value of type 'Int' to specified type 'Bool'"

(* --- sema: TODO(12-sema) exhaustiveness --- *)
let test_exhaustiveness () =
  has_error (shape ^ "let s = Shape.dot\nswitch s {\ncase .dot: print(0)\n}") "switch must be exhaustive";
  has_error (shape ^ "let s = Shape.dot\nswitch s {\ncase .circle(let r): print(r)\ncase .rect(let w, let h): print(w)\n}")
    "switch must be exhaustive";
  (* the same case twice covers ONE case, not two *)
  has_error "enum E { case a, b }\nlet e = E.a\nswitch e {\ncase .a: print(1)\ncase .a: print(2)\n}"
    "switch must be exhaustive"

let test_exhaustive_accepts () =
  (* covering every case, or adding a default, must NOT report anything *)
  accepted full;
  accepted "enum E { case a, b }\nlet e = E.a\nswitch e {\ncase .a: print(1)\ndefault: print(0)\n}"

(* --- silgen: TODO(12) the dispatch chain --- *)
let test_dispatch_sil () =
  let s = sil full in
  Alcotest.(check int) "the subject is read once" 1 (count s "enum_tag");
  Alcotest.(check int) "one test per case" 3 (count s "cond_br");
  Alcotest.(check bool) "arms join at one block" true (contains s "br bb1")

let test_payload_sil () =
  let s = sil full in
  Alcotest.(check int) "three payload reads" 3 (count s "enum_payload");
  Alcotest.(check bool) "the second value is #1" true (contains s "enum_payload %4, #1");
  (* an exhaustive switch with no default runs out of cases: nothing may fall through *)
  Alcotest.(check bool) "the chain ends unreachable" true (contains s "unreachable")

let test_ignore_sil () =
  (* `_` binds nothing, so the payload is never extracted *)
  let s = sil "enum E { case a(Int), b }\nvar t = 0\nlet e = E.a(5)\nswitch e {\ncase .a(_): t = 1\ncase .b: t = 2\n}" in
  Alcotest.(check int) "no payload read for _" 0 (count s "enum_payload");
  Alcotest.(check int) "still one tag read" 1 (count s "enum_tag")

let () =
  Alcotest.run "switch"
    [
      ( "sema-switch",
        [
          Alcotest.test_case "well-typed switches" `Quick test_accept;
          Alcotest.test_case "case + binding rules" `Quick test_pattern_rules;
          Alcotest.test_case "a binding is arm-local" `Quick test_binding_scope;
        ] );
      ( "sema-exhaustive",
        [
          Alcotest.test_case "missing cases are refused" `Quick test_exhaustiveness;
          Alcotest.test_case "complete switches are quiet" `Quick test_exhaustive_accepts;
        ] );
      ( "silgen-switch",
        [
          Alcotest.test_case "one tag read, one test/case" `Quick test_dispatch_sil;
          Alcotest.test_case "payload bound per arm" `Quick test_payload_sil;
          Alcotest.test_case "_ extracts nothing" `Quick test_ignore_sil;
        ] );
    ]
