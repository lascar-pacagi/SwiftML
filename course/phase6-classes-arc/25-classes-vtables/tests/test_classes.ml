(* Alcotest unit tests for concept-25: classes, vtable layout, dispatch lowering. *)

let front (src : string) : Ast.program * Diagnostics.sink =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  (p, d)

let msgs (d : Diagnostics.sink) : string list =
  List.rev_map (fun (e : Diagnostics.t) -> e.Diagnostics.message) d.Diagnostics.diags

let lower (src : string) : Sil.modul =
  let p, d = front src in
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  Silgen.lower p

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.fold_left
    (fun acc (f : Sil.func) ->
      List.fold_left (fun acc (b : Sil.block) -> acc + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) acc f.Sil.blocks)
    0 m.Sil.funcs

let hier = "class Animal { var legs: Int\n  init(_ l: Int) { legs = l }\n  func sound() -> Int { return 0 }\n  func describe() -> Int { return legs * 100 + sound() } }\nclass Dog: Animal { override func sound() -> Int { return 7 }\n  func fetch() -> Int { return 1 } }\n"

let test_vtable_layout () =
  let m = lower (hier ^ "print(Dog(4).describe())") in
  let dog = List.find (fun (cl : Types.class_layout) -> cl.Types.cl_name = "Dog") m.Sil.classes in
  (* slots: inherited numbering, override replaced IN PLACE, new method appended *)
  Alcotest.(check (list string)) "Dog's vtable impls" [ "Dog.sound"; "Animal.describe"; "Dog.fetch" ] dog.Types.cl_impls;
  Alcotest.(check int) "fields inherited" 1 (List.length dog.Types.cl_fields);
  Alcotest.(check (list string)) "module verifies (vtable names real functions)" [] (Sil.verify m)

let test_override_diags () =
  let _, d = front "class A { var x: Int\n  init() { x = 1 }\n  func f() -> Int { return 1 } }\nclass B: A { func f() -> Int { return 2 } }" in
  Alcotest.(check bool) "missing override keyword" true
    (List.mem "overriding declaration requires an 'override' keyword" (msgs d));
  let _, d2 = front "class A { var x: Int\n  init() { x = 1 } }\nclass B: A { override func g() -> Int { return 2 } }" in
  Alcotest.(check bool) "override of nothing" true
    (List.mem "method does not override any method from its superclass" (msgs d2))

let test_dispatch_shapes () =
  let m = lower (hier ^ "let a: Animal = Dog(4)\nprint(a.sound())") in
  Alcotest.(check bool) "a class_method dispatch exists" true
    (count_instr (function Sil.Apply_class _ -> true | _ -> false) m >= 1);
  Alcotest.(check bool) "an upcast exists (Dog -> Animal)" true
    (count_instr (function Sil.Upcast _ -> true | _ -> false) m >= 1);
  Alcotest.(check bool) "construction allocates" true
    (count_instr (function Sil.Alloc_ref _ -> true | _ -> false) m >= 1)

let test_optimizer_safe () =
  let m = Opt.optimize (lower (hier ^ "let a: Animal = Dog(2)\nprint(a.describe())")) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m);
  Alcotest.(check bool) "vtable impls survive -O" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "Dog.sound") m.Sil.funcs)

let () =
  Alcotest.run "classes"
    [
      ("vtable", [ Alcotest.test_case "layout: inherit/override/append" `Quick test_vtable_layout;
                   Alcotest.test_case "override diagnostics" `Quick test_override_diags ]);
      ("dispatch", [ Alcotest.test_case "SIL shapes" `Quick test_dispatch_shapes ]);
      ("optimizer", [ Alcotest.test_case "-O keeps vtables valid" `Quick test_optimizer_safe ]);
    ]
