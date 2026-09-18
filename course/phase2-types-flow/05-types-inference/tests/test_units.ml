(* Alcotest unit tests for sema's pieces, called DIRECTLY. `sema.ml` keeps everything top-level
   and threads an explicit `ctx`, so each hole can be checked on its own instead of only through
   a whole program — a failure here names the function, not just "the checker is wrong".

   ONE CASE PER RULE, not one per function. `infer` is written arm by arm, so its report has to
   be readable arm by arm: a learner who has done `+` but not the comparisons should see the
   `+` line go green. A case that bundled four rules would hide three of them behind the first
   failure — red must be localisable, green must be visible.

   RED until the matching TODO(05x) is filled; GREEN against solution/sema.ml. *)

let sp = Token.dummy_span
let int_ n = Ast.Int_lit (n, sp)
let dbl_ f = Ast.Double_lit (f, sp)
let bool_ b = Ast.Bool_lit (b, sp)
let str_ s = Ast.String_lit (s, sp)
let var_ x = Ast.Var (x, sp)
let neg_ e = Ast.Unary (Ast.Neg, e, sp)
let bin_ op a b = Ast.Binary (op, a, b, sp)
let add_ a b = bin_ Ast.Add a b

let ty =
  Alcotest.testable
    (fun fmt t -> Format.pp_print_string fmt (Types.string_of_ty t))
    Types.equal

(* Every case starts from the same context: `i : Int` is already bound, so a test can use a
   typed VARIABLE (which never flexes) as well as a literal (which does). *)
let fresh () =
  let d = Diagnostics.create () in
  let cx = Sema.create d in
  Hashtbl.replace cx.Sema.environment "i" (Types.TInt, false);
  (cx, d)

let messages d =
  List.map
    (fun (x : Diagnostics.t) -> x.Diagnostics.message)
    (Diagnostics.all d)

(* A synthesis rule holds when `infer` gives the node this type AND says nothing. The silence
   half matters: an arm that returns the right type but also reports is still wrong. *)
let infers what e expected =
  let cx, d = fresh () in
  let got = Sema.infer cx e in
  Alcotest.(check ty) what expected got.Tast.ty;
  Alcotest.(check (list string)) (what ^ ", silently") [] (messages d)

(* Every arm that can fail must REPORT, not just return a plausible type — and inference keeps
   going, so one bad name does not hide the rest of the file. A silent arm is the failure mode
   these catch: it returns a type and says nothing. *)
let reports what e expected =
  let cx, d = fresh () in
  ignore (Sema.infer cx e);
  match messages d with
  | [ m ] -> Alcotest.(check string) what expected m
  | l ->
      Alcotest.failf "%s: expected exactly one diagnostic, got %d" what
        (List.length l)

(* -- TODO(05a) ---------------------------------------------------------- *)
(* Two things decide whether a tree may flex to Double: every LEAF must be an integer literal,
   and every OPERATOR must be one that Double has. The two are separate cases because they are
   separate mistakes. *)

let yes what e = Alcotest.(check bool) what true (Sema.is_int_literal e)
let no what e = Alcotest.(check bool) what false (Sema.is_int_literal e)

let test_literal_leaves () =
  yes "1" (int_ 1);
  yes "-1" (neg_ (int_ 1));
  yes "1 + 2 * 3" (add_ (int_ 1) (bin_ Ast.Mul (int_ 2) (int_ 3)));
  no "i (a typed variable never flexes)" (var_ "i");
  no "1.0 (already a Double)" (dbl_ 1.0);
  no "1 + i (one non-literal leaf is enough)" (add_ (int_ 1) (var_ "i"));
  no "true" (bool_ true)

(* Swift has no `%` on Double: swiftc answers `let d: Double = 1 % 2` with "'%' is unavailable:
   For floating point numbers use truncatingRemainder instead". `/` is fine — Double division
   exists — so the rule is about which operators Double has, not about division. *)
let test_double_operators () =
  yes "1 / 2 (Double has /)" (bin_ Ast.Div (int_ 1) (int_ 2));
  no "1 % 2 (Double has no %)" (bin_ Ast.Mod (int_ 1) (int_ 2));
  no "1 + 1 % 2 (one % anywhere is enough)"
    (add_ (int_ 1) (bin_ Ast.Mod (int_ 1) (int_ 2)))

(* -- TODO(05b) ---------------------------------------------------------- *)
let u l tl r tr = Sema.unify l tl r tr
let unifies what expected got = Alcotest.(check (option ty)) what expected got

let test_unify_equal () =
  unifies "Int/Int" (Some Types.TInt) (u (int_ 1) Types.TInt (int_ 2) Types.TInt);
  unifies "String/String" (Some Types.TString)
    (u (str_ "a") Types.TString (str_ "b") Types.TString)

let test_unify_flexes () =
  unifies "1 + 2.0" (Some Types.TDouble)
    (u (int_ 1) Types.TInt (dbl_ 2.0) Types.TDouble);
  unifies "2.0 + 1" (Some Types.TDouble)
    (u (dbl_ 2.0) Types.TDouble (int_ 1) Types.TInt)

let test_unify_refuses () =
  unifies "i + 2.0 (a var does not flex)" None
    (u (var_ "i") Types.TInt (dbl_ 2.0) Types.TDouble);
  unifies "1 + true" None (u (int_ 1) Types.TInt (bool_ true) Types.TBool)

(* -- TODO(05c) ---------------------------------------------------------- *)
(* The literal arms are GIVEN, so this one is green from the start — it is the anchor that says
   the harness itself works when everything below it is red. *)
let test_literals () =
  infers "1" (int_ 1) Types.TInt;
  infers "1.5" (dbl_ 1.5) Types.TDouble;
  infers "true" (bool_ true) Types.TBool;
  infers "\"s\"" (str_ "s") Types.TString

let test_var () = infers "i" (var_ "i") Types.TInt

let test_var_reports () =
  reports "nope" (var_ "nope") "cannot find 'nope' in scope"

let test_neg_int () = infers "-1" (neg_ (int_ 1)) Types.TInt
let test_neg_double () = infers "-1.5" (neg_ (dbl_ 1.5)) Types.TDouble

(* the unary arm must ask whether the operand is numeric, not just pass its type through *)
let test_neg_reports () =
  reports "-true" (neg_ (bool_ true))
    "unary operator '-' cannot be applied to an operand of type 'Bool'"

let test_arith_int () = infers "1 + 2" (add_ (int_ 1) (int_ 2)) Types.TInt

let test_arith_double () =
  infers "1.5 * 2.0" (bin_ Ast.Mul (dbl_ 1.5) (dbl_ 2.0)) Types.TDouble

(* the coercion, reached through `unify` — this is the rule concept 05 exists for *)
let test_arith_flexes () =
  infers "1 + 2.0" (add_ (int_ 1) (dbl_ 2.0)) Types.TDouble

(* `+` is the one arithmetic operator String also has *)
let test_concat () =
  infers "\"a\" + \"b\"" (add_ (str_ "a") (str_ "b")) Types.TString

(* a comparison's result does not depend on its operands' type *)
let test_compare_int () =
  infers "1 < 2" (bin_ Ast.Lt (int_ 1) (int_ 2)) Types.TBool

let test_compare_double () =
  infers "1.5 == 2.5" (bin_ Ast.Eq (dbl_ 1.5) (dbl_ 2.5)) Types.TBool

(* the two wordings: swiftc picks by whether the operands agree *)
let test_binop_reports () =
  reports "1 + true" (add_ (int_ 1) (bool_ true))
    "binary operator '+' cannot be applied to operands of type 'Int' and 'Bool'"

let test_binop_reports_same () =
  reports "true < false" (bin_ Ast.Lt (bool_ true) (bool_ false))
    "binary operator '<' cannot be applied to two 'Bool' operands"

(* `print` must INFER its argument, or an error inside it is swallowed *)
let test_print_infers_arg () =
  reports "print(nope)"
    (Ast.Call ("print", [ var_ "nope" ], sp))
    "cannot find 'nope' in scope"

let test_print_arity () =
  reports "print(1, 2)"
    (Ast.Call ("print", [ int_ 1; int_ 2 ], sp))
    "print(_:) expects exactly one argument"

let test_unknown_function () =
  reports "foo()" (Ast.Call ("foo", [], sp)) "cannot find 'foo' in scope"

(* -- TODO(05g) ---------------------------------------------------------- *)
(* `e as T`: the type is written, so the operand is CHECKED against it. That is why a literal
   may be ascribed to Double and a typed variable may not. *)
let test_ascribe () =
  infers "1 as Double" (Ast.Ascribe (int_ 1, "Double", sp)) Types.TDouble

let test_ascribe_var_reports () =
  reports "i as Double"
    (Ast.Ascribe (var_ "i", "Double", sp))
    "cannot convert value of type 'Int' to specified type 'Double'"

let test_ascribe_unknown_type () =
  reports "1 as Foo"
    (Ast.Ascribe (int_ 1, "Foo", sp))
    "cannot find type 'Foo' in scope"

(* -- TODO(05d) ---------------------------------------------------------- *)
(* Checking succeeds when it is silent AND the node it hands back carries the expected type —
   that record of the choice is what SILGen reads instead of guessing. *)
let accepts what e expected =
  let cx, d = fresh () in
  let got = Sema.check_expr cx e expected in
  Alcotest.(check ty) (what ^ " carries its type") expected got.Tast.ty;
  Alcotest.(check (list string)) (what ^ ", silently") [] (messages d)

let test_check_literal () = accepts "1 against Double" (int_ 1) Types.TDouble

let test_check_pushes_down () =
  accepts "1 + 2 against Double" (add_ (int_ 1) (int_ 2)) Types.TDouble

(* A comparison does NOT receive the expectation: its result is Bool whatever the operands are,
   so pushing Bool into `1` and `2` would reject a legal program. It must reach the
   fall-through — infer, then compare — instead. *)
let test_check_comparison () =
  accepts "1 < 2 against Bool" (bin_ Ast.Lt (int_ 1) (int_ 2)) Types.TBool

let test_check_reports () =
  let cx, d = fresh () in
  ignore (Sema.check_expr cx (str_ "s") Types.TInt);
  match messages d with
  | [ m ] ->
      Alcotest.(check string)
        "wording" "cannot convert value of type 'String' to specified type 'Int'"
        m
  | l -> Alcotest.failf "expected exactly one diagnostic, got %d" (List.length l)

(* -- TODO(05e) ---------------------------------------------------------- *)
let let_ ?annot ~is_var name value =
  Ast.Let { name; is_var; annot; value; span = sp }

let bound cx name =
  match Hashtbl.find_opt cx.Sema.environment name with
  | Some b -> b
  | None -> Alcotest.failf "'%s' was not bound" name

let test_let_binds () =
  let cx, d = fresh () in
  ignore (Sema.check_stmt cx (let_ ~is_var:false "x" (int_ 1)));
  Alcotest.(check ty) "inferred type" Types.TInt (fst (bound cx "x"));
  Alcotest.(check bool) "a let is not a var" false (snd (bound cx "x"));
  Alcotest.(check (list string)) "silently" [] (messages d)

let test_var_binds () =
  let cx, _ = fresh () in
  ignore (Sema.check_stmt cx (let_ ~is_var:true "y" (int_ 1)));
  Alcotest.(check bool) "a var is a var" true (snd (bound cx "y"))

(* the annotation drives `check_expr`, so the literal takes the annotated type, not Int *)
let test_annotated_let () =
  let cx, d = fresh () in
  ignore (Sema.check_stmt cx (let_ ~annot:"Double" ~is_var:false "z" (int_ 1)));
  Alcotest.(check ty) "annotated type" Types.TDouble (fst (bound cx "z"));
  Alcotest.(check (list string)) "silently" [] (messages d)

let test_annotated_let_reports () =
  let cx, d = fresh () in
  ignore (Sema.check_stmt cx (let_ ~annot:"Double" ~is_var:false "z" (var_ "i")));
  Alcotest.(check (list string))
    "an Int variable does not flex"
    [ "cannot convert value of type 'Int' to specified type 'Double'" ]
    (messages d)

let test_assign_to_let_reports () =
  let cx, d = fresh () in
  ignore (Sema.check_stmt cx (let_ ~is_var:false "x" (int_ 1)));
  ignore (Sema.check_stmt cx (Ast.Assign { name = "x"; value = int_ 2; span = sp }));
  Alcotest.(check (list string))
    "wording"
    [ "cannot assign to value: 'x' is a 'let' constant" ]
    (messages d)

let case name f = Alcotest.test_case name `Quick f

let () =
  Alcotest.run "sema-units"
    [
      ( "05a",
        [
          case "is_int_literal: literal leaves" test_literal_leaves;
          case "is_int_literal: Double's ops" test_double_operators;
        ] );
      ( "05b",
        [
          case "unify: equal types agree" test_unify_equal;
          case "unify: a literal flexes" test_unify_flexes;
          case "unify: nothing else does" test_unify_refuses;
        ] );
      ( "05c",
        [
          case "infer: literals (given)" test_literals;
          case "infer: a bound name" test_var;
          case "infer: unknown name reports" test_var_reports;
          case "infer: -1 is Int" test_neg_int;
          case "infer: -1.5 is Double" test_neg_double;
          case "infer: -true reports" test_neg_reports;
          case "infer: 1 + 2 is Int" test_arith_int;
          case "infer: 1.5 * 2.0 is Double" test_arith_double;
          case "infer: 1 + 2.0 flexes" test_arith_flexes;
          case "infer: \"a\" + \"b\" is String" test_concat;
          case "infer: 1 < 2 is Bool" test_compare_int;
          case "infer: 1.5 == 2.5 is Bool" test_compare_double;
          case "infer: 1 + true reports" test_binop_reports;
          case "infer: true < false reports" test_binop_reports_same;
          case "infer: print infers its arg" test_print_infers_arg;
          case "infer: print arity reports" test_print_arity;
          case "infer: unknown function reports" test_unknown_function;
        ] );
      ( "05g",
        [
          case "as: 1 as Double is Double" test_ascribe;
          case "as: i as Double reports" test_ascribe_var_reports;
          case "as: unknown type reports" test_ascribe_unknown_type;
        ] );
      ( "05d",
        [
          case "check_expr: 1 takes Double" test_check_literal;
          case "check_expr: pushes into +" test_check_pushes_down;
          case "check_expr: comparison falls through" test_check_comparison;
          case "check_expr: mismatch reports" test_check_reports;
        ] );
      ( "05e",
        [
          case "check_stmt: let binds" test_let_binds;
          case "check_stmt: var is a var" test_var_binds;
          case "check_stmt: annotation drives check" test_annotated_let;
          case "check_stmt: bad annotation reports" test_annotated_let_reports;
          case "check_stmt: assign to let reports" test_assign_to_let_reports;
        ] );
    ]
