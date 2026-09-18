(* Alcotest unit tests for sema's pieces, called DIRECTLY. `sema.ml` keeps everything top-level
   and threads an explicit `ctx`, so each hole can be checked on its own instead of only through
   a whole program — a failure here names the function, not just "the checker is wrong".

   ONE CASE PER RULE, not one per function. `infer` is written arm by arm, so its report has to
   be readable arm by arm: a learner who has done `+` but not the comparisons should see the
   `+` line go green. A case that bundled four rules would hide three of them behind the first
   failure — red must be localisable, green must be visible.

   EXHAUSTIVE OVER THE OPERATOR TABLE. A rule that holds for `+` is asserted for `-`, `*` and
   `/` too, in both operand positions, because "it worked for `+`" is exactly how a `match` arm
   ends up covering one operator and guessing at the rest. Every expectation below was asked of
   real swiftc first (`let a = 1 - 2.0` accepted, `let d = 1 % 2.0` rejected, and so on).

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

(* the operator table, split the way the rules split it *)
let arith = [ Ast.Add; Ast.Sub; Ast.Mul; Ast.Div ]
let equality = [ Ast.Eq; Ast.Ne ]
let ordered = [ Ast.Lt; Ast.Le; Ast.Gt; Ast.Ge ]

let ty =
  Alcotest.testable
    (fun fmt t -> Format.pp_print_string fmt (Types.string_of_ty t))
    Types.equal

(* Labels are what a failure prints, so each one spells the tree it came from. *)
let lbl op l r = Printf.sprintf "%s %s %s" l (Ast.string_of_binop op) r

let two op t =
  Printf.sprintf "binary operator '%s' cannot be applied to two '%s' operands"
    (Ast.string_of_binop op) t

let mixed op a b =
  Printf.sprintf
    "binary operator '%s' cannot be applied to operands of type '%s' and '%s'"
    (Ast.string_of_binop op) a b

let convert a b =
  Printf.sprintf "cannot convert value of type '%s' to specified type '%s'" a b

(* Every case starts from the same context: `i : Int` is already bound, so a test can use a
   typed VARIABLE (which never flexes) as well as a literal (which does). *)
let fresh () =
  let d = Diagnostics.create () in
  let cx = Sema.create d in
  Hashtbl.replace cx.Sema.environment "i" (Types.TInt, false);
  Hashtbl.replace cx.Sema.environment "d" (Types.TDouble, false);
  Hashtbl.replace cx.Sema.environment "s" (Types.TString, false);
  Hashtbl.replace cx.Sema.environment "b" (Types.TBool, false);
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

(* Two different mistakes hide behind "the diagnostic is wrong", and a plain list comparison
   shows them the same way. Say which: an arm that ACCEPTED the program is a rule that is
   missing, an arm that rejected it with other words is a rule that is right and a sentence that
   is not. *)
let diagnosed what expected got =
  match got with
  | [ m ] when String.equal m expected -> ()
  | [] ->
      Alcotest.failf "%s: accepted it silently.@.Expected it to report:@.  %s" what
        expected
  | [ m ] ->
      Alcotest.failf
        "%s: rejected it, but with the wrong wording.@.  said: %s@.  want: %s" what
        m expected
  | l ->
      Alcotest.failf "%s: expected exactly one diagnostic, got %d:@.%s" what
        (List.length l)
        (String.concat "\n" (List.map (fun m -> "  " ^ m) l))

(* Every arm that can fail must REPORT, not just return a plausible type — and inference keeps
   going, so one bad name does not hide the rest of the file. A silent arm is the failure mode
   these catch: it returns a type and says nothing. *)
let reports what e expected =
  let cx, d = fresh () in
  ignore (Sema.infer cx e);
  diagnosed what expected (messages d)

(* -- TODO(05a) ---------------------------------------------------------- *)
(* Two things decide whether a tree may flex to Double: every LEAF must be an integer literal,
   and every OPERATOR must be one that Double has. They are separate cases because they are
   separate mistakes. *)

(* `Expected: false / Received: true` says nothing about which rule broke, so these spell the
   verdict out. The label names the tree, and for a `no` it names the reason too. *)
let yes what e =
  if not (Sema.is_int_literal e) then
    Alcotest.failf
      "%s@.  is_int_literal said NO, expected YES — every leaf is an integer \
       literal@.  and every operator is one that Double has."
      what

let no what e =
  if Sema.is_int_literal e then
    Alcotest.failf
      "%s@.  is_int_literal said YES, expected NO — this tree cannot flex to \
       Double."
      what

let test_literal_leaves () =
  yes "1" (int_ 1);
  yes "-1" (neg_ (int_ 1));
  yes "-(-1)" (neg_ (neg_ (int_ 1)));
  yes "1 + 2 * 3" (add_ (int_ 1) (bin_ Ast.Mul (int_ 2) (int_ 3)));
  no "i (a typed variable never flexes)" (var_ "i");
  no "-i" (neg_ (var_ "i"));
  no "1.0 (already a Double)" (dbl_ 1.0);
  no "\"s\"" (str_ "s");
  no "true" (bool_ true);
  List.iter
    (fun op ->
      no (lbl op "1" "i") (bin_ op (int_ 1) (var_ "i"));
      no (lbl op "i" "1") (bin_ op (var_ "i") (int_ 1)))
    arith

(* Swift has no `%` on Double: swiftc answers `let d: Double = 1 % 2` with "'%' is unavailable:
   For floating point numbers use truncatingRemainder instead". `+ - * /` are all fine — Double
   has them — so the rule is about which operators Double has, not about arithmetic in general.
   Comparisons never reach this predicate: their result is Bool, so there is nothing to flex. *)
let test_double_operators () =
  List.iter
    (fun op -> yes (lbl op "1" "2") (bin_ op (int_ 1) (int_ 2)))
    arith;
  no "1 % 2 (Double has no %)" (bin_ Ast.Mod (int_ 1) (int_ 2));
  List.iter
    (fun op ->
      no
        (lbl op "1" "(1 % 2)")
        (bin_ op (int_ 1) (bin_ Ast.Mod (int_ 1) (int_ 2)));
      no
        (lbl op "(1 % 2)" "1")
        (bin_ op (bin_ Ast.Mod (int_ 1) (int_ 2)) (int_ 1)))
    arith

(* -- TODO(05b) ---------------------------------------------------------- *)
let u l tl r tr = Sema.unify l tl r tr
let unifies what expected got = Alcotest.(check (option ty)) what expected got

let test_unify_equal () =
  unifies "Int/Int" (Some Types.TInt) (u (int_ 1) Types.TInt (int_ 2) Types.TInt);
  unifies "Double/Double" (Some Types.TDouble)
    (u (dbl_ 1.0) Types.TDouble (dbl_ 2.0) Types.TDouble);
  unifies "String/String" (Some Types.TString)
    (u (str_ "a") Types.TString (str_ "b") Types.TString);
  unifies "Bool/Bool" (Some Types.TBool)
    (u (bool_ true) Types.TBool (bool_ false) Types.TBool)

(* the coercion, in BOTH operand positions — one-sided code passes half a test *)
let test_unify_flexes () =
  unifies "1 / 2.0" (Some Types.TDouble)
    (u (int_ 1) Types.TInt (dbl_ 2.0) Types.TDouble);
  unifies "2.0 / 1" (Some Types.TDouble)
    (u (dbl_ 2.0) Types.TDouble (int_ 1) Types.TInt);
  unifies "(1 + 2) / 3.0" (Some Types.TDouble)
    (u (add_ (int_ 1) (int_ 2)) Types.TInt (dbl_ 3.0) Types.TDouble)

let test_unify_refuses () =
  unifies "i / 2.0 (a var does not flex)" None
    (u (var_ "i") Types.TInt (dbl_ 2.0) Types.TDouble);
  unifies "2.0 / i" None (u (dbl_ 2.0) Types.TDouble (var_ "i") Types.TInt);
  unifies "1 / true" None (u (int_ 1) Types.TInt (bool_ true) Types.TBool);
  unifies "1 / \"s\"" None (u (int_ 1) Types.TInt (str_ "s") Types.TString);
  unifies "1.0 / \"s\"" None
    (u (dbl_ 1.0) Types.TDouble (str_ "s") Types.TString);
  unifies "true / \"s\"" None
    (u (bool_ true) Types.TBool (str_ "s") Types.TString)

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

let test_neg () =
  infers "-1" (neg_ (int_ 1)) Types.TInt;
  infers "-1.5" (neg_ (dbl_ 1.5)) Types.TDouble;
  infers "-i" (neg_ (var_ "i")) Types.TInt

(* the unary arm must ask whether the operand is numeric, not just pass its type through *)
let test_neg_reports () =
  reports "-true" (neg_ (bool_ true))
    "unary operator '-' cannot be applied to an operand of type 'Bool'";
  reports "-\"s\"" (neg_ (str_ "s"))
    "unary operator '-' cannot be applied to an operand of type 'String'"

let test_arith_int () =
  List.iter
    (fun op -> infers (lbl op "1" "2") (bin_ op (int_ 1) (int_ 2)) Types.TInt)
    arith

let test_arith_double () =
  List.iter
    (fun op ->
      infers (lbl op "1.5" "2.0") (bin_ op (dbl_ 1.5) (dbl_ 2.0)) Types.TDouble)
    arith

(* The rule concept 05 exists for, asserted for every operator that has it and in both operand
   positions. swiftc accepts `1 + 2.0`, `1 - 2.0`, `1 * 2.0` and `1 / 2.0` alike. *)
let test_arith_flexes () =
  List.iter
    (fun op ->
      infers (lbl op "1" "2.0") (bin_ op (int_ 1) (dbl_ 2.0)) Types.TDouble;
      infers (lbl op "2.0" "1") (bin_ op (dbl_ 2.0) (int_ 1)) Types.TDouble;
      infers
        (lbl op "(1 + 2)" "3.0")
        (bin_ op (add_ (int_ 1) (int_ 2)) (dbl_ 3.0))
        Types.TDouble)
    arith

(* The flex must be RECORDED, not just concluded. A Binary node that says Double over an operand
   node that still says Int is PLAN.md §0.1's bug — the checker knew, the tree did not say so,
   and SILGen had to work it out again (and got it wrong). `unify` decides; a second walk has to
   write the decision into the flexed side. swiftc calls that walk CSApply. *)
let flexed_operands what e =
  let cx, _ = fresh () in
  match (Sema.infer cx e).Tast.e with
  | Tast.Binary (_, l, r) ->
      Alcotest.(check ty) (what ^ ": left operand") Types.TDouble l.Tast.ty;
      Alcotest.(check ty) (what ^ ": right operand") Types.TDouble r.Tast.ty
  | _ -> Alcotest.failf "%s: expected a Binary node" what

let test_flex_is_recorded () =
  List.iter
    (fun op ->
      flexed_operands (lbl op "1" "2.0") (bin_ op (int_ 1) (dbl_ 2.0));
      flexed_operands (lbl op "2.0" "1") (bin_ op (dbl_ 2.0) (int_ 1)))
    arith

(* A typed variable is the other half of the same rule: it must NOT flex. True of every
   operator, comparisons included — `unify` returns None and the operator never gets a type. *)
let test_var_never_flexes () =
  List.iter
    (fun op ->
      reports (lbl op "i" "2.0")
        (bin_ op (var_ "i") (dbl_ 2.0))
        (mixed op "Int" "Double");
      reports (lbl op "2.0" "i")
        (bin_ op (dbl_ 2.0) (var_ "i"))
        (mixed op "Double" "Int"))
    ((arith @ [ Ast.Mod ]) @ equality @ ordered)

let test_mod_int () = infers "1 % 2" (bin_ Ast.Mod (int_ 1) (int_ 2)) Types.TInt

(* `%` is Int-only, so it neither flexes nor accepts Doubles — swiftc rejects all three *)
let test_mod_never_flexes () =
  reports "1 % 2.0" (bin_ Ast.Mod (int_ 1) (dbl_ 2.0)) (mixed Ast.Mod "Int" "Double");
  reports "2.0 % 1" (bin_ Ast.Mod (dbl_ 2.0) (int_ 1)) (mixed Ast.Mod "Double" "Int");
  reports "1.5 % 2.0"
    (bin_ Ast.Mod (dbl_ 1.5) (dbl_ 2.0))
    (two Ast.Mod "Double")

(* `+` is the one arithmetic operator String also has *)
let test_concat () =
  infers "\"a\" + \"b\"" (add_ (str_ "a") (str_ "b")) Types.TString

let test_arith_string_reports () =
  List.iter
    (fun op ->
      reports
        (lbl op "\"a\"" "\"b\"")
        (bin_ op (str_ "a") (str_ "b"))
        (two op "String"))
    [ Ast.Sub; Ast.Mul; Ast.Div; Ast.Mod ]

let test_arith_bool_reports () =
  List.iter
    (fun op ->
      reports
        (lbl op "true" "false")
        (bin_ op (bool_ true) (bool_ false))
        (two op "Bool"))
    (arith @ [ Ast.Mod ])

(* a comparison's result does not depend on its operands' type — and `==`/`!=` take any one *)
let test_equality () =
  List.iter
    (fun op ->
      infers (lbl op "1" "2") (bin_ op (int_ 1) (int_ 2)) Types.TBool;
      infers (lbl op "1.5" "2.5") (bin_ op (dbl_ 1.5) (dbl_ 2.5)) Types.TBool;
      infers (lbl op "\"a\"" "\"b\"") (bin_ op (str_ "a") (str_ "b")) Types.TBool;
      infers
        (lbl op "true" "false")
        (bin_ op (bool_ true) (bool_ false))
        Types.TBool)
    equality

(* `< <= > >=` need an ORDER, which Bool has not: swiftc rejects `true < false` *)
let test_ordered () =
  List.iter
    (fun op ->
      infers (lbl op "1" "2") (bin_ op (int_ 1) (int_ 2)) Types.TBool;
      infers (lbl op "1.5" "2.5") (bin_ op (dbl_ 1.5) (dbl_ 2.5)) Types.TBool;
      infers (lbl op "\"a\"" "\"b\"") (bin_ op (str_ "a") (str_ "b")) Types.TBool)
    ordered

let test_ordered_bool_reports () =
  List.iter
    (fun op ->
      reports
        (lbl op "true" "false")
        (bin_ op (bool_ true) (bool_ false))
        (two op "Bool"))
    ordered

(* the flex happens inside `unify`, so it reaches the comparisons too: `1 < 2.0` is legal *)
let test_comparisons_flex () =
  List.iter
    (fun op ->
      infers (lbl op "1" "2.0") (bin_ op (int_ 1) (dbl_ 2.0)) Types.TBool;
      infers (lbl op "2.0" "1") (bin_ op (dbl_ 2.0) (int_ 1)) Types.TBool)
    (equality @ ordered)

(* the two wordings: swiftc picks by whether the operands agree *)
let test_mixed_reports () =
  reports "1 + true" (add_ (int_ 1) (bool_ true)) (mixed Ast.Add "Int" "Bool");
  reports "1 + \"s\"" (add_ (int_ 1) (str_ "s")) (mixed Ast.Add "Int" "String");
  reports "1 < true" (bin_ Ast.Lt (int_ 1) (bool_ true)) (mixed Ast.Lt "Int" "Bool");
  reports "1 == \"s\""
    (bin_ Ast.Eq (int_ 1) (str_ "s"))
    (mixed Ast.Eq "Int" "String")

(* THE WHOLE TABLE, the rejecting half: every operator against every unequal pair of types, with
   typed VARIABLES so nothing can flex and the only question left is the operator's. 11 x 12 =
   132 combinations, and real swiftc rejects every one of them (checked). It does not word them
   all the same way — overload resolution gives `s - i` "cannot convert value of type 'String'
   to expected argument type 'Int'" and `d != b` "conflicting arguments to generic parameter
   'Self'" — because Swift's operators are generic functions and it is reporting on the
   candidates it tried. We have one operator table and no overloads, so we give one wording;
   the verdict is what matches. *)
let typed =
  [ ("i", Types.TInt); ("d", Types.TDouble); ("s", Types.TString); ("b", Types.TBool) ]

let every_op = arith @ [ Ast.Mod ] @ equality @ ordered

let test_mixed_all_ops () =
  List.iter
    (fun op ->
      List.iter
        (fun (ln, lt) ->
          List.iter
            (fun (rn, rt) ->
              if lt <> rt then
                reports (lbl op ln rn)
                  (bin_ op (var_ ln) (var_ rn))
                  (mixed op (Types.string_of_ty lt) (Types.string_of_ty rt)))
            typed)
        typed)
    every_op

(* and the same sweep for operands that DO agree: every operator on each of the four types,
   accepted where the table allows it and reported as "two 'X' operands" where it does not *)
let test_same_type_all_ops () =
  List.iter
    (fun (n, t) ->
      List.iter
        (fun op ->
          let e = bin_ op (var_ n) (var_ n) and what = lbl op n n in
          match (op, t) with
          | (Ast.Add | Ast.Sub | Ast.Mul | Ast.Div), (Types.TInt | Types.TDouble)
            ->
              infers what e t
          | Ast.Add, Types.TString -> infers what e Types.TString
          | Ast.Mod, Types.TInt -> infers what e Types.TInt
          | (Ast.Eq | Ast.Ne), _ -> infers what e Types.TBool
          | (Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge), (Types.TInt | Types.TDouble | Types.TString)
            ->
              infers what e Types.TBool
          | _ -> reports what e (two op (Types.string_of_ty t)))
        every_op)
    typed

(* `print` must INFER its argument, or an error inside it is swallowed *)
let test_print_infers_arg () =
  reports "print(nope)"
    (Ast.Call ("print", [ var_ "nope" ], sp))
    "cannot find 'nope' in scope"

let test_print_arity () =
  reports "print(1, 2)"
    (Ast.Call ("print", [ int_ 1; int_ 2 ], sp))
    "print(_:) expects exactly one argument";
  reports "print()" (Ast.Call ("print", [], sp))
    "print(_:) expects exactly one argument"

let test_unknown_function () =
  reports "foo()" (Ast.Call ("foo", [], sp)) "cannot find 'foo' in scope"

(* -- TODO(05g) ---------------------------------------------------------- *)
(* `e as T`: the type is written, so the operand is CHECKED against it. That is why a literal
   may be ascribed to Double and a typed variable may not. *)
let as_ e t = Ast.Ascribe (e, t, sp)

let test_ascribe () =
  infers "1 as Int" (as_ (int_ 1) "Int") Types.TInt;
  infers "1 as Double" (as_ (int_ 1) "Double") Types.TDouble;
  infers "(1 + 2) as Double" (as_ (add_ (int_ 1) (int_ 2)) "Double") Types.TDouble;
  infers "1.5 as Double" (as_ (dbl_ 1.5) "Double") Types.TDouble;
  infers "true as Bool" (as_ (bool_ true) "Bool") Types.TBool;
  infers "\"s\" as String" (as_ (str_ "s") "String") Types.TString

let test_ascribe_reports () =
  reports "i as Double" (as_ (var_ "i") "Double") (convert "Int" "Double");
  reports "1 as Bool" (as_ (int_ 1) "Bool") (convert "Int" "Bool");
  reports "1.5 as Int" (as_ (dbl_ 1.5) "Int") (convert "Double" "Int")

let test_ascribe_unknown_type () =
  reports "1 as Foo" (as_ (int_ 1) "Foo") "cannot find type 'Foo' in scope"

(* -- TODO(05d) ---------------------------------------------------------- *)
(* Checking succeeds when it is silent AND the node it hands back carries the expected type —
   that record of the choice is what SILGen reads instead of guessing. *)
let accepts what e expected =
  let cx, d = fresh () in
  let got = Sema.check_expr cx e expected in
  Alcotest.(check ty) (what ^ " carries its type") expected got.Tast.ty;
  Alcotest.(check (list string)) (what ^ ", silently") [] (messages d)

let refuses what e expected message =
  let cx, d = fresh () in
  ignore (Sema.check_expr cx e expected);
  diagnosed what message (messages d)

let test_check_literal () =
  accepts "1 against Int" (int_ 1) Types.TInt;
  accepts "1 against Double" (int_ 1) Types.TDouble

let test_check_literal_reports () =
  refuses "1 against Bool" (int_ 1) Types.TBool (convert "Int" "Bool");
  refuses "1 against String" (int_ 1) Types.TString (convert "Int" "String")

let test_check_pushes_down () =
  List.iter
    (fun op ->
      accepts
        (lbl op "1" "2" ^ " against Double")
        (bin_ op (int_ 1) (int_ 2))
        Types.TDouble)
    arith;
  accepts "-1 against Double" (neg_ (int_ 1)) Types.TDouble;
  accepts "1 + 2 * 3 against Double"
    (add_ (int_ 1) (bin_ Ast.Mul (int_ 2) (int_ 3)))
    Types.TDouble

(* `%` may be pushed down at Int and nowhere else *)
let test_check_mod () =
  accepts "1 % 2 against Int" (bin_ Ast.Mod (int_ 1) (int_ 2)) Types.TInt

let test_check_mod_reports () =
  refuses "1 % 2 against Double"
    (bin_ Ast.Mod (int_ 1) (int_ 2))
    Types.TDouble (convert "Int" "Double")

(* A comparison does NOT receive the expectation: its result is Bool whatever the operands are,
   so pushing Bool into `1` and `2` would reject a legal program. It must reach the
   fall-through — infer, then compare — instead. *)
let test_check_comparison () =
  List.iter
    (fun op ->
      accepts
        (lbl op "1" "2" ^ " against Bool")
        (bin_ op (int_ 1) (int_ 2))
        Types.TBool)
    (equality @ ordered)

let test_check_reports () =
  refuses "\"s\" against Int" (str_ "s") Types.TInt (convert "String" "Int");
  refuses "i against Double" (var_ "i") Types.TDouble (convert "Int" "Double");
  refuses "true against Int" (bool_ true) Types.TInt (convert "Bool" "Int")

(* -- TODO(05e) ---------------------------------------------------------- *)
let let_ ?annot ~is_var name value =
  Ast.Let { name; is_var; annot; value; span = sp }

let assign_ name value = Ast.Assign { name; value; span = sp }

let bound cx name =
  match Hashtbl.find_opt cx.Sema.environment name with
  | Some b -> b
  | None -> Alcotest.failf "'%s' was not bound" name

let test_let_binds () =
  let cx, d = fresh () in
  ignore (Sema.check_stmt cx (let_ ~is_var:false "x" (int_ 1)));
  ignore (Sema.check_stmt cx (let_ ~is_var:true "y" (dbl_ 1.5)));
  Alcotest.(check ty) "x is Int" Types.TInt (fst (bound cx "x"));
  Alcotest.(check ty) "y is Double" Types.TDouble (fst (bound cx "y"));
  Alcotest.(check bool) "a let is not a var" false (snd (bound cx "x"));
  Alcotest.(check bool) "a var is a var" true (snd (bound cx "y"));
  Alcotest.(check (list string)) "silently" [] (messages d)

(* the annotation drives `check_expr`, so the literal takes the annotated type, not Int *)
let test_annotated_let () =
  let cx, d = fresh () in
  ignore (Sema.check_stmt cx (let_ ~annot:"Double" ~is_var:false "z" (int_ 1)));
  ignore
    (Sema.check_stmt cx (let_ ~annot:"Double" ~is_var:false "w" (add_ (int_ 1) (int_ 2))));
  Alcotest.(check ty) "z is Double" Types.TDouble (fst (bound cx "z"));
  Alcotest.(check ty) "w is Double" Types.TDouble (fst (bound cx "w"));
  Alcotest.(check (list string)) "silently" [] (messages d)

let test_annotated_let_reports () =
  let cx, d = fresh () in
  ignore (Sema.check_stmt cx (let_ ~annot:"Double" ~is_var:false "z" (var_ "i")));
  Alcotest.(check (list string))
    "an Int variable does not flex"
    [ convert "Int" "Double" ] (messages d)

let test_unknown_annotation () =
  let cx, d = fresh () in
  ignore (Sema.check_stmt cx (let_ ~annot:"Foo" ~is_var:false "z" (int_ 1)));
  Alcotest.(check (list string))
    "the type name is resolved too"
    [ "cannot find type 'Foo' in scope" ]
    (messages d)

let test_assign_checks_value () =
  let cx, d = fresh () in
  ignore (Sema.check_stmt cx (let_ ~annot:"Double" ~is_var:true "m" (int_ 0)));
  (* the target's type is the expectation, so an Int literal flexes on assignment too *)
  ignore (Sema.check_stmt cx (assign_ "m" (int_ 3)));
  Alcotest.(check (list string)) "silently" [] (messages d);
  ignore (Sema.check_stmt cx (assign_ "m" (str_ "s")));
  Alcotest.(check (list string))
    "a mismatch reports" [ convert "String" "Double" ] (messages d)

let test_assign_to_let_reports () =
  let cx, d = fresh () in
  ignore (Sema.check_stmt cx (let_ ~is_var:false "x" (int_ 1)));
  ignore (Sema.check_stmt cx (assign_ "x" (int_ 2)));
  Alcotest.(check (list string))
    "wording"
    [ "cannot assign to value: 'x' is a 'let' constant" ]
    (messages d)

let test_assign_unknown_reports () =
  let cx, d = fresh () in
  ignore (Sema.check_stmt cx (assign_ "nope" (int_ 2)));
  Alcotest.(check (list string))
    "the target must exist"
    [ "cannot find 'nope' in scope" ]
    (messages d)

(* a bare expression statement is inferred, so an error inside it still surfaces *)
let test_expr_stmt () =
  let cx, d = fresh () in
  ignore (Sema.check_stmt cx (Ast.Expr_stmt (Ast.Call ("print", [ int_ 1 ], sp), sp)));
  Alcotest.(check (list string)) "silently" [] (messages d);
  ignore (Sema.check_stmt cx (Ast.Expr_stmt (var_ "nope", sp)));
  Alcotest.(check (list string))
    "and reports what is inside"
    [ "cannot find 'nope' in scope" ]
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
          case "infer: -e keeps its type" test_neg;
          case "infer: -true reports" test_neg_reports;
          case "infer: + - * / on Int" test_arith_int;
          case "infer: + - * / on Double" test_arith_double;
          case "infer: + - * / flex a literal" test_arith_flexes;
          case "infer: the flex is recorded" test_flex_is_recorded;
          case "infer: a var will not flex" test_var_never_flexes;
          case "infer: 1 % 2 is Int" test_mod_int;
          case "infer: % on a Double reports" test_mod_never_flexes;
          case "infer: + joins Strings" test_concat;
          case "infer: - * / % on String report" test_arith_string_reports;
          case "infer: arithmetic on Bool reports" test_arith_bool_reports;
          case "infer: == != on any one type" test_equality;
          case "infer: < <= > >= when ordered" test_ordered;
          case "infer: < <= > >= on Bool report" test_ordered_bool_reports;
          case "infer: comparisons flex too" test_comparisons_flex;
          case "infer: mixed operands report" test_mixed_reports;
          case "infer: every op, mixed operands" test_mixed_all_ops;
          case "infer: every op, equal operands" test_same_type_all_ops;
          case "infer: print infers its arg" test_print_infers_arg;
          case "infer: print arity reports" test_print_arity;
          case "infer: unknown function reports" test_unknown_function;
        ] );
      ( "05g",
        [
          case "as: an identity coercion" test_ascribe;
          case "as: a mismatch reports" test_ascribe_reports;
          case "as: unknown type reports" test_ascribe_unknown_type;
        ] );
      ( "05d",
        [
          case "check_expr: a literal takes it" test_check_literal;
          case "check_expr: a literal refuses" test_check_literal_reports;
          case "check_expr: pushes into + - * /" test_check_pushes_down;
          case "check_expr: % at Int" test_check_mod;
          case "check_expr: % not at Double" test_check_mod_reports;
          case "check_expr: comparisons fall through" test_check_comparison;
          case "check_expr: mismatch reports" test_check_reports;
        ] );
      ( "05e",
        [
          case "check_stmt: let and var bind" test_let_binds;
          case "check_stmt: annotation drives check" test_annotated_let;
          case "check_stmt: bad annotated value" test_annotated_let_reports;
          case "check_stmt: unknown type reports" test_unknown_annotation;
          case "check_stmt: assign checks value" test_assign_checks_value;
          case "check_stmt: assign to let reports" test_assign_to_let_reports;
          case "check_stmt: assign unknown reports" test_assign_unknown_reports;
          case "check_stmt: expr stmt is inferred" test_expr_stmt;
        ] );
    ]
