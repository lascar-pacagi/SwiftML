(* Alcotest for concept 25. The three holes separate here: `vtable 25a` needs only Sema, and
   `dispatch 25b` and `emission 25c` add one stage each on top of it. *)

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

let llvm (src : string) : string = Irgen.emit_llvm (lower src)

let instrs (m : Sil.modul) : Sil.instr list =
  List.concat_map
    (fun (f : Sil.func) -> List.concat_map (fun (b : Sil.block) -> List.map snd b.Sil.instrs) f.Sil.blocks)
    m.Sil.funcs

let count_instr (pred : Sil.instr -> bool) (m : Sil.modul) : int =
  List.length (List.filter pred (instrs m))

let has (needle : string) (hay : string) : bool =
  let n = String.length needle and h = String.length hay in
  let rec go i = i + n <= h && (String.sub hay i n = needle || go (i + 1)) in
  n = 0 || go 0

let hier =
  "class Animal { var legs: Int\n\
  \  init(_ l: Int) { legs = l }\n\
  \  func sound() -> Int { return 0 }\n\
  \  func describe() -> Int { return legs * 100 + sound() } }\n\
   class Dog: Animal { override func sound() -> Int { return 7 }\n\
  \  func fetch() -> Int { return 1 } }\n"

let class_layout (m : Sil.modul) (n : string) : Types.class_layout =
  List.find (fun (cl : Types.class_layout) -> cl.Types.cl_name = n) m.Sil.classes

(* ---- TODO(25a): the vtable build ---- *)

let test_layout () =
  let m = lower (hier ^ "print(Dog(4).legs)") in
  let dog = class_layout m "Dog" in
  Alcotest.(check (list string))
    "Dog's vtable impls" [ "Dog.sound"; "Animal.describe"; "Dog.fetch" ] dog.Types.cl_impls;
  Alcotest.(check (list string))
    "Dog's slot names" [ "sound"; "describe"; "fetch" ] (List.map (fun (n, _, _) -> n) dog.Types.cl_methods);
  Alcotest.(check (list string))
    "Animal's is unchanged" [ "Animal.sound"; "Animal.describe" ]
    (class_layout m "Animal").Types.cl_impls;
  Alcotest.(check int) "fields inherited" 1 (List.length dog.Types.cl_fields);
  Alcotest.(check (list string)) "module verifies" [] (Sil.verify m)

let test_deep_layout () =
  let m = lower (hier ^ "class Cub: Dog { override func fetch() -> Int { return 2 } }\nprint(Cub(1).legs)") in
  (* three levels, ONE numbering: the grandchild's override lands in the slot Dog appended *)
  Alcotest.(check (list string))
    "Cub's impls" [ "Dog.sound"; "Animal.describe"; "Cub.fetch" ] (class_layout m "Cub").Types.cl_impls

let test_override_diags () =
  let _, d =
    front "class A { var x: Int\n  init() { x = 1 }\n  func f() -> Int { return 1 } }\nclass B: A { func f() -> Int { return 2 } }"
  in
  Alcotest.(check bool) "missing override keyword" true
    (List.mem "overriding declaration requires an 'override' keyword" (msgs d));
  let _, d2 = front "class A { var x: Int\n  init() { x = 1 } }\nclass B: A { override func g() -> Int { return 2 } }" in
  Alcotest.(check bool) "override of nothing" true
    (List.mem "method does not override any method from its superclass" (msgs d2));
  let _, d3 =
    front "class A { var x: Int\n  init() { x = 1 }\n  func f() -> Int { return 1 } }\nclass B: A { override func f() -> Bool { return true } }"
  in
  Alcotest.(check bool) "signature mismatch is not an override" true
    (List.mem "method does not override any method from its superclass" (msgs d3))

(* ---- TODO(25b): the dispatch lowering ---- *)

let test_dispatch_slots () =
  let m = lower (hier ^ "let a: Animal = Dog(4)\nprint(a.sound())\nprint(a.describe())\nprint(Dog(1).fetch())") in
  let slots =
    List.filter_map (function Sil.Apply_class (_, s, _) -> Some s | _ -> None) (instrs m)
  in
  (* the slot comes from the receiver's STATIC type, so #0, #1 through Animal and #2 through Dog;
     the fourth is `describe`'s own self-call to `sound()` *)
  Alcotest.(check (list int)) "slots dispatched" [ 0; 0; 1; 2 ] (List.sort compare slots);
  Alcotest.(check bool) "construction allocates" true (count_instr (function Sil.Alloc_ref _ -> true | _ -> false) m >= 2);
  Alcotest.(check bool) "an upcast exists" true (count_instr (function Sil.Upcast _ -> true | _ -> false) m >= 1)

let test_self_call_dispatches () =
  let m = lower (hier ^ "print(Dog(4).describe())") in
  let desc = List.find (fun (f : Sil.func) -> f.Sil.fname = "Animal.describe") m.Sil.funcs in
  let body = List.concat_map (fun (b : Sil.block) -> List.map snd b.Sil.instrs) desc.Sil.blocks in
  Alcotest.(check int) "sound() is a vtable dispatch" 1
    (List.length (List.filter (function Sil.Apply_class (_, 0, _) -> true | _ -> false) body));
  Alcotest.(check int) "and not a direct call" 0
    (List.length (List.filter (function Sil.Func_ref _ -> true | _ -> false) body))

let test_struct_not_dispatched () =
  let m = lower "struct P { var x: Int\n  func get() -> Int { return x } }\nprint(P(x: 4).get())" in
  Alcotest.(check int) "value types have no vtable" 0
    (count_instr (function Sil.Apply_class _ -> true | _ -> false) m)

(* ---- TODO(25c): the LLVM emission ---- *)

let test_emission () =
  let ll = llvm (hier ^ "let a: Animal = Dog(4)\nprint(a.describe())") in
  Alcotest.(check bool) "the object's word 0 is loaded" true (has "%t2 = load ptr, ptr %v" ll);
  Alcotest.(check bool) "the slot is indexed" true (has "getelementptr ptr, ptr %t2, i64 1" ll);
  Alcotest.(check bool) "the loaded pointer is called" true (has "call i64 %t4(ptr " ll);
  Alcotest.(check bool) "one table per class" true
    (has "@vtbl.Animal = private unnamed_addr constant [2 x ptr]" ll
    && has "@vtbl.Dog = private unnamed_addr constant [3 x ptr]" ll)

let test_void_emission () =
  let ll = llvm "class C { var n: Int\n  init() { n = 0 }\n  func bump() { n = n + 1 } }\nlet c = C()\nc.bump()\nprint(c.n)" in
  Alcotest.(check bool) "a void method is a bare call void" true (has "call void %t" ll)

(* ---- the optimizer must not lose a vtable's impls ---- *)

let test_optimizer_safe () =
  let m = Opt.optimize (lower (hier ^ "let a: Animal = Dog(2)\nprint(a.describe())")) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m);
  Alcotest.(check bool) "vtable impls survive -O" true
    (List.exists (fun (f : Sil.func) -> f.Sil.fname = "Dog.sound") m.Sil.funcs)

(* ---- carried-forward front-end rules (given code) ---- *)

let test_subset_refusals () =
  let _, d = front "class C { var x: Int\n  init() { x = 1 } }\nprint(C())\nprint(C() == C())" in
  Alcotest.(check bool) "print of a class" true
    (List.mem "cannot print a value of type 'C' (only Int, Double, Bool and String)" (msgs d));
  Alcotest.(check bool) "== on two objects" true
    (List.mem "binary operator '==' cannot be applied to two 'C' operands" (msgs d))

let test_let_property () =
  let _, d = front "class C { let k: Int\n  init() { k = 1 } }\nlet c = C()\nc.k = 5" in
  Alcotest.(check bool) "a let property is frozen" true
    (List.mem "cannot assign to property: 'k' is a 'let' constant" (msgs d));
  let _, d2 = front "class C { let k: Int\n  init() { k = 1 }\n  func get() -> Int { return k } }\nprint(C().get())" in
  Alcotest.(check bool) "but its own init may write it" false (Diagnostics.has_errors d2)

let () =
  Alcotest.run "classes"
    [
      ( "vtable 25a",
        [ Alcotest.test_case "inherit; override; append" `Quick test_layout;
          Alcotest.test_case "three levels, one numbering" `Quick test_deep_layout;
          Alcotest.test_case "the override diagnostics" `Quick test_override_diags ] );
      ( "dispatch 25b",
        [ Alcotest.test_case "slots come from static types" `Quick test_dispatch_slots;
          Alcotest.test_case "a self-call dispatches too" `Quick test_self_call_dispatches;
          Alcotest.test_case "a struct method does not" `Quick test_struct_not_dispatched ] );
      ( "emission 25c",
        [ Alcotest.test_case "three loads and a call" `Quick test_emission;
          Alcotest.test_case "void is a bare call void" `Quick test_void_emission ] );
      ("optimizer", [ Alcotest.test_case "-O keeps vtables valid" `Quick test_optimizer_safe ]);
      ( "given rules",
        [ Alcotest.test_case "print/== on an object" `Quick test_subset_refusals;
          Alcotest.test_case "a let stored property" `Quick test_let_property ] );
    ]
