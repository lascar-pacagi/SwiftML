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

(* An unknown name is REPORTED, not raised — and inference keeps going so one bad name does not
   hide the rest of the file. *)
let test_infer_reports () =
  let d = Diagnostics.create () in
  let cx = Sema.create d in
  ignore (Sema.infer cx (var_ "nope"));
  match Diagnostics.all d with
  | [ x ] -> Alcotest.(check string) "wording" "cannot find 'nope' in scope" x.Diagnostics.message
  | l -> Alcotest.failf "expected exactly one diagnostic, got %d" (List.length l)

(* -- TODO(05d) ---------------------------------------------------------- *)
let test_check_expr () =
  let d = Diagnostics.create () in
  let cx = Sema.create d in
  Sema.check_expr cx (int_ 1) Types.TDouble;          (* the coercion: silent *)
  Sema.check_expr cx (add_ (int_ 1) (int_ 2)) Types.TDouble;
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
                Alcotest.test_case "infer: unknown name reported" `Quick test_infer_reports ]);
      ("05d", [ Alcotest.test_case "check_expr: pushes down" `Quick test_check_expr ]);
      ("05e", [ Alcotest.test_case "check_stmt: binds and rejects" `Quick test_check_stmt ]);
    ]
