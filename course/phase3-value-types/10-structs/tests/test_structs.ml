(* Alcotest unit tests for concept 10, one group per TODO.  The early groups stop at their
   own compiler stage: a learner can finish and test lexing before parsing works, and finish
   parsing before Sema works.  The lowering groups inspect SIL or LLVM text in process. *)

let lex_kinds (src : string) : string list =
  let diagnostics = Diagnostics.create () in
  Lexer.tokenize (Lexer.create src diagnostics)
  |> List.map (fun (token : Token.t) -> Token.string_of_kind token.Token.kind)

let parse (src : string) : Ast.program =
  let diagnostics = Diagnostics.create () in
  Parser.parse_program
    (Parser.create (Lexer.tokenize (Lexer.create src diagnostics)) diagnostics)

let ast (src : string) : string = Ast.dump_program (parse src)

let front (src : string) : Ast.program * Diagnostics.sink =
  let d = Diagnostics.create () in
  let p =
    Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d)
  in
  Sema.check p d;
  (p, d)

let errors (src : string) : string list =
  let _, d = front src in
  Diagnostics.all d
  |> List.filter (fun (x : Diagnostics.t) ->
      x.Diagnostics.severity = Diagnostics.Error)
  |> List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message)

let sil_module (src : string) : Sil.modul =
  let p, _ = front src in
  Silgen.lower p

let sil (src : string) : string = Sil.string_of_module (sil_module src)

let llvm (src : string) : string =
  let p, _ = front src in
  Irgen.emit_llvm (Silgen.lower p)

let point = "struct Point {\n  var x: Int\n  var y: Int\n}\n"
let line = point ^ "struct Line {\n  var a: Point\n  var b: Point\n}\n"

let accepted src =
  Alcotest.(check (list string))
    (Printf.sprintf "accept %S" src)
    [] (errors src)

let has_error src msg =
  Alcotest.(check bool)
    (Printf.sprintf "%S => %S" src msg)
    true
    (List.mem msg (errors src))

let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  m = 0 || go 0

let count hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i acc =
    if i + m > n then acc
    else go (i + 1) (if String.sub hay i m = needle then acc + 1 else acc)
  in
  if m = 0 then 0 else go 0 0

let sil_has src needle =
  Alcotest.(check bool)
    (Printf.sprintf "sil has %S" needle)
    true
    (contains (sil src) needle)

let sil_lacks src needle =
  Alcotest.(check bool)
    (Printf.sprintf "sil lacks %S" needle)
    false
    (contains (sil src) needle)

let ir_has src needle =
  Alcotest.(check bool)
    (Printf.sprintf "ir has %S" needle)
    true
    (contains (llvm src) needle)

(* --- TODO(10a): tokens --- *)

let test_struct_tokens () =
  Alcotest.(check (list string))
    "struct, dot, semicolon, and range"
    [
      "struct";
      "ident(P)";
      "{";
      "}";
      "newline";
      "ident(p)";
      ".";
      "ident(x)";
      "newline";
      "int(0)";
      "..<";
      "int(1)";
      "eof";
    ]
    (lex_kinds "struct P {}; p.x\n0..<1")

(* --- TODO(10b): declarations --- *)

let test_parse_struct_decl () =
  Alcotest.(check string)
    "ordered fields retain var/let and written types"
    "(struct Box (value:Point let visible:Bool))"
    (ast "struct Box { var value: Point; let visible: Bool }")

(* --- TODO(10c): uses --- *)

let test_parse_argument_labels () =
  Alcotest.(check string)
    "labels and positional arguments remain distinct"
    "(let p (Point x:1 y:2))\n(add 2 3)"
    (ast "let p = Point(x: 1, y: 2)\nadd(2, 3)")

let test_parse_member_reads () =
  Alcotest.(check string)
    "postfix member reads chain left to right" "(print (. (. line b) x))"
    (ast "print(line.b.x)")

let test_parse_member_write () =
  Alcotest.(check string)
    "one-level write retains its expression" "(.= p x (+ (. p x) 1))"
    (ast "p.x = p.x + 1")

(* --- TODO(10d): registry and layouts --- *)

let test_struct_registry () =
  accepted
    "func identity(_ box: Box) -> Box { return box }\n\
     struct Box { var value: Point }\n\
     struct Point { var x: Int }";
  has_error "struct Bad { var value: Missing }"
    "cannot find type 'Missing' in scope";
  has_error "struct A {}\nstruct A {}" "invalid redeclaration of 'A'"

(* --- TODO(10e): initialization and reads --- *)
let test_member_read_from_parameter () =
  accepted
    "struct Pair { var count: Int; var ready: Bool }\n\
     func count(_ pair: Pair) -> Int { return pair.count }\n\
     func ready(_ pair: Pair) -> Bool { return pair.ready }"

let test_member_read_errors_without_init () =
  has_error
    "struct Point { var x: Int }\n\
     func read(_ point: Point) -> Int { return point.z }"
    "value of type 'Point' has no member 'z'";
  has_error "func read(_ number: Int) -> Int { return number.x }"
    "value of type 'Int' has no member 'x'"

let test_accept () =
  accepted (point ^ "let p = Point(x: 3, y: 4)\nprint(p.x)");
  accepted
    (point
   ^ "func sum(_ p: Point) -> Int { return p.x + p.y }\n\
      print(sum(Point(x: 1, y: 2)))");
  accepted
    (line
   ^ "let l = Line(a: Point(x: 0, y: 0), b: Point(x: 7, y: 9))\nprint(l.b.x)");
  accepted
    "struct S {\n\
    \  let x: Int\n\
    \  var y: Int\n\
     }\n\
     let s = S(x: 1, y: 2)\n\
     print(s.x)"

let test_init_rules () =
  has_error
    (point ^ "let p = Point(x: \"s\", y: 2)")
    "cannot convert value of type 'String' to specified type 'Int'";
  has_error
    (point ^ "let p = Point(1, 2)")
    "missing argument label 'x:' in call";
  has_error
    (point ^ "let p = Point(z: 1, y: 2)")
    "incorrect argument label in call (have 'z:', expected 'x:')";
  has_error
    (point ^ "let p = Point(x: 1)")
    "'Point' initializer expects 2 argument(s) but 1 given";
  has_error "let p = Nope(x: 1)" "cannot find 'Nope' in scope"

let test_member_rules () =
  has_error
    (point ^ "let p = Point(x: 1, y: 2)\nprint(p.z)")
    "value of type 'Point' has no member 'z'";
  has_error "let n = 3\nprint(n.x)" "value of type 'Int' has no member 'x'"

let test_backend_guards () =
  (* two programs swiftc treats differently from us, refused in sema so the back end never
     sees an aggregate it cannot compare or print (each used to crash the compiler) *)
  has_error
    (point ^ "let p = Point(x: 1, y: 2)\nprint(p == p)")
    "binary operator '==' cannot be applied to two 'Point' operands";
  has_error
    (point ^ "let p = Point(x: 1, y: 2)\nprint(p)")
    "cannot print a value of type 'Point' (only Int, Double, Bool and String)"

(* --- TODO(10f): member writes --- *)

let test_member_write_rules () =
  accepted (point ^ "var p = Point(x: 1, y: 2)\np.x = 5");
  (* value semantics is enforced through `let`: a let-bound struct's fields can't be assigned *)
  has_error
    (point ^ "let p = Point(x: 1, y: 2)\np.x = 5")
    "cannot assign to property: 'p' is a 'let' constant";
  (* and a `let` FIELD is immutable through any binding, `var` included *)
  has_error
    "struct S {\n  let x: Int\n  var y: Int\n}\nvar s = S(x: 1, y: 2)\ns.x = 2"
    "cannot assign to property: 'x' is a 'let' constant";
  has_error
    (point ^ "var p = Point(x: 1, y: 2)\np.x = \"bad\"")
    "cannot convert value of type 'String' to specified type 'Int'"

(* --- TODO(10g): SIL member read --- *)
let test_read_sil () =
  let src = point ^ "let p = Point(x: 3, y: 4)\nprint(p.y)" in
  sil_has src "struct_extract";
  sil_has src ", #1 $Int";
  sil_lacks src "struct_element_addr"

let test_read_nested_sil () =
  let s =
    sil
      (line
     ^ "let l = Line(a: Point(x: 0, y: 0), b: Point(x: 7, y: 9))\nprint(l.b.x)"
      )
  in
  Alcotest.(check int) "two extracts for l.b.x" 2 (count s "struct_extract");
  Alcotest.(check bool)
    "inner Point first (#1 $Point)" true (contains s ", #1 $Point")

(* --- TODO(10h): SIL member write --- *)
let test_write_sil () =
  let src = point ^ "var p = Point(x: 1, y: 2)\np.x = 9" in
  let main =
    List.find
      (fun (function_ : Sil.func) -> function_.Sil.fname = "main")
      (sil_module src).Sil.funcs
  in
  let instructions =
    List.concat_map
      (fun (block : Sil.block) -> List.rev block.Sil.instrs)
      (List.rev main.Sil.blocks)
  in
  let result_of wanted =
    fst (List.find (fun (_, instruction) -> instruction = wanted) instructions)
  in
  let p_address = result_of (Sil.Alloc_stack "p") in
  let nine = result_of (Sil.Int_lit 9) in
  let field_address, base_address =
    List.find_map
      (fun (result, instruction) ->
        match instruction with
        | Sil.Struct_element_addr (base, 0) -> Some (result, base)
        | _ -> None)
      instructions
    |> Option.get
  in
  Alcotest.(check int) "field address starts at p's slot" p_address base_address;
  Alcotest.(check bool)
    "the value 9 is stored through that field address" true
    (List.exists
       (fun (_, instruction) -> instruction = Sil.Store (nine, field_address))
       instructions);
  Alcotest.(check bool)
    "a write does not extract a value" false
    (List.exists
       (fun (_, instruction) ->
         match instruction with Sil.Struct_extract _ -> true | _ -> false)
       instructions)

let test_write_own_slot () =
  (* value semantics in the SIL: q's write addresses q's slot, and p's slot is never addressed *)
  let module_ =
    sil_module (point ^ "var p = Point(x: 1, y: 2)\nvar q = p\nq.x = 99")
  in
  let main =
    List.find
      (fun (function_ : Sil.func) -> function_.Sil.fname = "main")
      module_.Sil.funcs
  in
  let instructions =
    List.concat_map
      (fun (block : Sil.block) -> List.rev block.Sil.instrs)
      (List.rev main.Sil.blocks)
  in
  let address_of name =
    fst
      (List.find
         (fun (_, instruction) -> instruction = Sil.Alloc_stack name)
         instructions)
  in
  let field_bases =
    List.filter_map
      (fun (_, instruction) ->
        match instruction with
        | Sil.Struct_element_addr (base, 0) -> Some base
        | _ -> None)
      instructions
  in
  Alcotest.(check (list int))
    "only q's slot is addressed" [ address_of "q" ] field_bases;
  Alcotest.(check bool)
    "p's slot is not addressed" false
    (List.mem (address_of "p") field_bases)

(* --- TODO(10i): LLVM aggregates --- *)
let test_llvm_shape () =
  ir_has (point ^ "let p = Point(x: 1, y: 2)") "%Point = type { i64, i64 }";
  ir_has (point ^ "let p = Point(x: 1, y: 2)") "insertvalue %Point undef, i64";
  ir_has (point ^ "var p = Point(x: 1, y: 2)\nprint(p.x)") "extractvalue %Point";
  ir_has
    (point ^ "var p = Point(x: 1, y: 2)\np.x = 9\nprint(p.x)")
    "getelementptr %Point";
  ir_has
    (line ^ "let l = Line(a: Point(x: 0, y: 0), b: Point(x: 7, y: 9))")
    "%Line = type { %Point, %Point }"

let () =
  Alcotest.run "structs"
    [
      ( "lexer-structs",
        [
          Alcotest.test_case "struct, dot, semicolon" `Quick test_struct_tokens;
        ] );
      ( "parser-struct-decls",
        [
          Alcotest.test_case "stored properties in source order" `Quick
            test_parse_struct_decl;
        ] );
      ( "parser-struct-uses",
        [
          Alcotest.test_case "argument labels" `Quick test_parse_argument_labels;
          Alcotest.test_case "chained member reads" `Quick
            test_parse_member_reads;
          Alcotest.test_case "one-level member write" `Quick
            test_parse_member_write;
        ] );
      ( "sema-struct-decls",
        [
          Alcotest.test_case "names first, then field layouts" `Quick
            test_struct_registry;
        ] );
      ( "sema-struct-exprs",
        [
          Alcotest.test_case "member types without initializer" `Quick
            test_member_read_from_parameter;
          Alcotest.test_case "member errors without initializer" `Quick
            test_member_read_errors_without_init;
          Alcotest.test_case "well-typed struct programs" `Quick test_accept;
          Alcotest.test_case "memberwise init rules" `Quick test_init_rules;
          Alcotest.test_case "member access rules" `Quick test_member_rules;
          Alcotest.test_case "== and print refused up front" `Quick
            test_backend_guards;
        ] );
      ( "sema-member-write",
        [
          Alcotest.test_case "binding, field, and value checks" `Quick
            test_member_write_rules;
        ] );
      ( "silgen-member-read",
        [
          Alcotest.test_case "p.y is struct_extract #1" `Quick test_read_sil;
          Alcotest.test_case "l.b.x is two extracts" `Quick test_read_nested_sil;
        ] );
      ( "silgen-member-write",
        [
          Alcotest.test_case "p.x = 9 is element_addr #0" `Quick test_write_sil;
          Alcotest.test_case "q.x = 99 addresses q's slot" `Quick
            test_write_own_slot;
        ] );
      ( "irgen-structs",
        [ Alcotest.test_case "aggregate IR shape" `Quick test_llvm_shape ] );
    ]
