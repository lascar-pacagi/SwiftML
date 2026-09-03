(* Alcotest unit tests for sema's pieces, called DIRECTLY. `sema.ml` keeps everything top-level
   and threads an explicit `ctx`, so each hole can be checked on its own instead of only through
   a whole program — a failure here names the function, not just "the checker is wrong".

   RED until the matching TODO(05x) is filled; GREEN against solution/sema.ml. *)

let sp = Token.dummy_span
let int_ n = Ast.Int_lit (n, sp)
let dbl_ f = Ast.Double_lit (f, sp)
let var_ x = Ast.Var (x, sp)
let neg_ e = Ast.Unary (Ast.Neg, e, sp)
let add_ a b = Ast.Binary (Ast.Add, a, b, sp)
let ty = Alcotest.testable (fun fmt t -> Format.pp_print_string fmt (Types.string_of_ty t)) Types.equal

(* -- TODO(05a) ---------------------------------------------------------- *)
let test_is_int_literal () =
  let yes e = Alcotest.(check bool) "literal" true (Sema.is_int_literal e) in
  let no e = Alcotest.(check bool) "not literal" false (Sema.is_int_literal e) in
  yes (int_ 1);
  yes (neg_ (int_ 1));
  yes (add_ (int_ 1) (Ast.Binary (Ast.Mul, int_ 2, int_ 3, sp)));
  no (var_ "i");                    (* a typed variable never flexes *)
  no (dbl_ 1.0);                    (* already a Double, nothing to flex *)
  no (add_ (int_ 1) (var_ "i"));    (* one non-literal leaf is enough *)
  no (Ast.Bool_lit (true, sp))

(* -- TODO(05b) ---------------------------------------------------------- *)
let test_unify () =
  let u l tl r tr = Sema.unify l tl r tr in
  Alcotest.(check (option ty)) "Int/Int" (Some Types.TInt) (u (int_ 1) Types.TInt (int_ 2) Types.TInt);
  Alcotest.(check (option ty)) "String/String" (Some Types.TString)
    (u (Ast.String_lit ("a", sp)) Types.TString (Ast.String_lit ("b", sp)) Types.TString);
  (* the coercion, in both operand positions *)
  Alcotest.(check (option ty)) "literal flexes right" (Some Types.TDouble)
    (u (int_ 1) Types.TInt (dbl_ 2.0) Types.TDouble);
  Alcotest.(check (option ty)) "literal flexes left" (Some Types.TDouble)
    (u (dbl_ 2.0) Types.TDouble (int_ 1) Types.TInt);
  (* a variable of type Int does not *)
  Alcotest.(check (option ty)) "Int var vs Double" None
    (u (var_ "i") Types.TInt (dbl_ 2.0) Types.TDouble);
  Alcotest.(check (option ty)) "Int vs Bool" None
    (u (int_ 1) Types.TInt (Ast.Bool_lit (true, sp)) Types.TBool)

(* -- TODO(05c) ---------------------------------------------------------- *)
let test_infer () =
  let cx = Sema.create (Diagnostics.create ()) in
  Hashtbl.replace cx.Sema.env "i" (Types.TInt, false);
  Alcotest.(check ty) "a bound name" Types.TInt (Sema.infer cx (var_ "i"));
  Alcotest.(check ty) "int + int" Types.TInt (Sema.infer cx (add_ (int_ 1) (int_ 2)));
  Alcotest.(check ty) "literal + double" Types.TDouble (Sema.infer cx (add_ (int_ 1) (dbl_ 2.0)));
  Alcotest.(check ty) "comparison is Bool" Types.TBool
    (Sema.infer cx (Ast.Binary (Ast.Lt, int_ 1, int_ 2, sp)))

(* Every arm that can fail must REPORT, not just return a plausible type — and inference keeps
   going, so one bad name does not hide the rest of the file. One case per failing arm: a silent
   arm is the failure mode these catch (it returns a type and says nothing). *)
let reports what src expected =
  let d = Diagnostics.create () in
  let cx = Sema.create d in
  Hashtbl.replace cx.Sema.env "i" (Types.TInt, false);
  ignore (Sema.infer cx src);
  match List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message) (Diagnostics.all d) with
  | [ m ] -> Alcotest.(check string) what expected m
  | l -> Alcotest.failf "%s: expected exactly one diagnostic, got %d" what (List.length l)

let test_unknown_name () = reports "Var" (var_ "nope") "cannot find 'nope' in scope"

(* the unary arm must ask whether the operand is numeric, not just pass its type through *)
let test_unary_reports () =
  reports "Unary" (neg_ (Ast.Bool_lit (true, sp)))
    "unary operator '-' cannot be applied to an operand of type 'Bool'"

let test_binop_reports () =
  reports "Binary" (add_ (int_ 1) (Ast.Bool_lit (true, sp)))
    "binary operator '+' cannot be applied to operands of type 'Int' and 'Bool'"

(* `print` must INFER its argument, or an error inside it is swallowed *)
let test_print_infers_arg () =
  reports "print's argument" (Ast.Call ("print", [ var_ "nope" ], sp)) "cannot find 'nope' in scope"

let test_unknown_function () =
  reports "Call" (Ast.Call ("foo", [], sp)) "cannot find 'foo' in scope"

(* -- TODO(05d) ---------------------------------------------------------- *)
let test_check_expr () =
  let d = Diagnostics.create () in
  let cx = Sema.create d in
  Sema.check_expr cx (int_ 1) Types.TDouble;          (* the coercion: silent *)
  Sema.check_expr cx (add_ (int_ 1) (int_ 2)) Types.TDouble;
  (* A comparison does NOT receive the expectation: its result is Bool whatever the operands
     are, so pushing Bool into `1` and `2` would reject a legal program. It must reach the
     fall-through instead. *)
  Sema.check_expr cx (Ast.Binary (Ast.Lt, int_ 1, int_ 2, sp)) Types.TBool;
  Sema.check_expr cx (Ast.Binary (Ast.Eq, Ast.Bool_lit (true, sp), Ast.Bool_lit (false, sp), sp))
    Types.TBool;
  Alcotest.(check int) "no diagnostics yet" 0 (List.length (Diagnostics.all d));
  Sema.check_expr cx (Ast.String_lit ("s", sp)) Types.TInt;
  match Diagnostics.all d with
  | [ x ] ->
      Alcotest.(check string) "wording"
        "cannot convert value of type 'String' to specified type 'Int'" x.Diagnostics.message
  | l -> Alcotest.failf "expected exactly one diagnostic, got %d" (List.length l)

(* -- TODO(05e) ---------------------------------------------------------- *)
let test_check_stmt () =
  let d = Diagnostics.create () in
  let cx = Sema.create d in
  Sema.check_stmt cx (Ast.Let { name = "x"; is_var = false; annot = None; value = int_ 1; span = sp });
  (match Hashtbl.find_opt cx.Sema.env "x" with
  | Some (t, is_var) ->
      Alcotest.(check ty) "bound type" Types.TInt t;
      Alcotest.(check bool) "let is not a var" false is_var
  | None -> Alcotest.fail "x was not bound");
  Sema.check_stmt cx (Ast.Assign { name = "x"; value = int_ 2; span = sp });
  match Diagnostics.all d with
  | [ x ] ->
      Alcotest.(check string) "wording" "cannot assign to value: 'x' is a 'let' constant"
        x.Diagnostics.message
  | l -> Alcotest.failf "expected exactly one diagnostic, got %d" (List.length l)

let () =
  Alcotest.run "sema-units"
    [
      ("05a", [ Alcotest.test_case "is_int_literal: only literal trees" `Quick test_is_int_literal ]);
      ("05b", [ Alcotest.test_case "unify: one side may flex" `Quick test_unify ]);
      ("05c", [ Alcotest.test_case "infer: types synthesized" `Quick test_infer;
                Alcotest.test_case "infer: unknown name reports" `Quick test_unknown_name;
                Alcotest.test_case "infer: `-true` reports" `Quick test_unary_reports;
                Alcotest.test_case "infer: `1 + true` reports" `Quick test_binop_reports;
                Alcotest.test_case "infer: print infers its arg" `Quick test_print_infers_arg;
                Alcotest.test_case "infer: unknown function reports" `Quick test_unknown_function ]);
      ("05d", [ Alcotest.test_case "check_expr: pushes down" `Quick test_check_expr ]);
      ("05e", [ Alcotest.test_case "check_stmt: binds and rejects" `Quick test_check_stmt ]);
    ]
