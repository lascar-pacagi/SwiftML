(* Alcotest unit tests for concept 13, one group per hole so each is reachable on its own:
   sema-optionals (given: the optional rules), then the four TODO(13) silgen holes — the
   implicit wrap, force-unwrap, nil-coalescing and `if let` — read off the SIL text. *)

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
let f_opt = "func f(_ n: Int) -> Int? {\n  if n < 0 { return nil }\n  return n * 2\n}\n"

(* --- sema (given) --- *)
let test_accept () =
  accepted "let a: Int? = 5\nlet b: Int? = nil\nprint(a ?? 0)\nprint(a!)\nprint(b == nil)";
  accepted (f_opt ^ "if let r = f(5) { print(r) }\nprint(f(-1) ?? -1)");
  accepted "struct Box {\n  var v: Int?\n  var n: Int\n}\nvar b = Box(v: 3, n: 1)\nb.v = nil\nprint(b.v ?? -1)"

let test_nil_rules () =
  has_error "let n: Int = nil" "'nil' cannot be used with a non-optional type 'Int'";
  has_error "let n = 5\nprint(n!)" "cannot force-unwrap a non-optional value of type 'Int'";
  has_error "if let v = 3 { print(v) }" "initializer for conditional binding must have Optional type, not 'Int'"

let test_no_implicit_conv () =
  (* an Int? is not an Int: it does not convert, and it does not do arithmetic *)
  has_error "let a: Int? = 5\nlet n: Int = a" "cannot convert value of type 'Int?' to specified type 'Int'";
  has_error "let a: Int? = 5\nprint(a + 1)" "binary operator '+' cannot be applied to operands of type 'Int?' and 'Int'";
  (* two optionals cannot be compared (swiftc synthesizes that; we do not), nor can one be printed *)
  has_error "let a: Int? = 5\nlet b: Int? = 6\nprint(a == b)" "binary operator '==' cannot be applied to two 'Int?' operands";
  has_error "let a: Int? = 5\nprint(a)" "cannot print a value of type 'Int?' (only Int, Double, Bool and String)"

(* --- silgen: TODO(13) the implicit wrap --- *)
let test_wrap_sil () =
  sil_has "let a: Int? = 5" "enum #1 (%0) $Int?";
  sil_has "let b: Int? = nil" "enum #0 () $Int?";
  (* assigning to an optional var and to an optional FIELD both wrap — the two once-shipped
     miscompiles: a raw store corrupts the tag *)
  sil_has "var x: Int? = 5\nx = 7" "enum #1 (%4) $Int?";
  sil_has "struct Box {\n  var v: Int?\n  var n: Int\n}\nvar b = Box(v: 3, n: 1)\nb.v = nil" "enum #0 () $Int?"

let test_wrap_once_sil () =
  (* a value that is already optional passes through: one enum instruction, not two *)
  let s = sil "func g(_ o: Int?) -> Int { return 0 }\nlet a: Int? = 5\nlet n = g(a)" in
  Alcotest.(check int) "wrapped once" 1 (count s "= enum ")

(* --- silgen: TODO(13) force-unwrap --- *)
let test_force_sil () =
  let s = sil "let a: Int? = 5\nprint(a!)" in
  Alcotest.(check bool) "tests the tag" true (contains s "enum_tag");
  Alcotest.(check bool) "reads the payload" true (contains s "enum_payload");
  Alcotest.(check bool) "traps on none" true
    (contains s "trap \"Fatal error: Unexpectedly found nil while unwrapping an Optional value\"")

let test_force_llvm () =
  (* the trap lowers to llvm.trap, which is what makes the exit code 133 *)
  Alcotest.(check bool) "llvm.trap" true (contains (llvm "let a: Int? = nil\nprint(a!)") "@llvm.trap()")

(* --- silgen: TODO(13) nil-coalescing --- *)
let test_coalesce_sil () =
  let s = sil "let a: Int? = 5\nprint(a ?? 0)" in
  Alcotest.(check bool) "merges through a slot" true (contains s "alloc_stack $Int  // coalesce");
  Alcotest.(check int) "one diamond" 1 (count s "cond_br");
  Alcotest.(check bool) "loads the merged value" true (contains s "load")

let line_index (s : string) (needle : string) : int =
  let ls = String.split_on_char '\n' s in
  let rec go i = function [] -> -1 | l :: r -> if contains l needle then i else go (i + 1) r in
  go 0 ls

let test_coalesce_lazy_sil () =
  (* the default is evaluated only on the nil path: its work is inside the else block, so the
     `+` is emitted AFTER the tag test, not before it *)
  let s = sil "let a: Int? = 5\nlet n = 10\nprint(a ?? n + 1)" in
  let br = line_index s "cond_br" and add = line_index s "binop \"+\"" in
  Alcotest.(check bool) "both present" true (br >= 0 && add >= 0);
  Alcotest.(check bool) "the + is after the test" true (add > br)

(* --- silgen: TODO(13) if let --- *)
let test_iflet_sil () =
  let s = sil "let a: Int? = 5\nif let v = a { print(v) }" in
  Alcotest.(check bool) "tests the tag" true (contains s "enum_tag");
  Alcotest.(check bool) "binds v to the payload" true (contains s "alloc_stack $Int  // v");
  Alcotest.(check int) "one diamond" 1 (count s "cond_br")

let test_iflet_else_sil () =
  let s = sil "let a: Int? = nil\nif let v = a { print(v) } else { print(0) }" in
  Alcotest.(check int) "both arms join" 2 (count s "br bb2");
  Alcotest.(check bool) "payload read in the arm" true (contains s "enum_payload")

let () =
  Alcotest.run "optionals"
    [
      ( "sema-optionals",
        [
          Alcotest.test_case "well-typed optional programs" `Quick test_accept;
          Alcotest.test_case "nil, !, if let need a T?" `Quick test_nil_rules;
          Alcotest.test_case "Int? is not Int" `Quick test_no_implicit_conv;
        ] );
      ( "silgen-wrap",
        [
          Alcotest.test_case "let/var/field wrap to .some" `Quick test_wrap_sil;
          Alcotest.test_case "an Int? is not wrapped twice" `Quick test_wrap_once_sil;
        ] );
      ( "silgen-force-unwrap",
        [
          Alcotest.test_case "tag test, payload, trap" `Quick test_force_sil;
          Alcotest.test_case "the trap is llvm.trap" `Quick test_force_llvm;
        ] );
      ( "silgen-coalesce",
        [
          Alcotest.test_case "a diamond through a slot" `Quick test_coalesce_sil;
          Alcotest.test_case "the default is lazy" `Quick test_coalesce_lazy_sil;
        ] );
      ( "silgen-iflet",
        [
          Alcotest.test_case "tag test binds the payload" `Quick test_iflet_sil;
          Alcotest.test_case "with else, arms join" `Quick test_iflet_else_sil;
        ] );
    ]
