(* The solver's pieces, called directly — the suite that says WHICH hole is wrong.
   `unify` and `simplify` are testable before any search exists, so TODO(41a) and TODO(41b)
   go green one at a time. *)

let con t = Constraints.Con t
let v n = Constraints.Var n
let sp = Token.dummy_span

let ty =
  Alcotest.testable
    (fun ppf t -> Format.pp_print_string ppf (Constraints.string_of_ty t))
    ( = )

(* --- TODO(41a): unify --------------------------------------------------------------- *)

let test_unify_concrete () =
  let s = Cssolver.empty () in
  Alcotest.(check bool) "Int == Int" true (Cssolver.unify s (con Types.TInt) (con Types.TInt));
  Alcotest.(check bool) "Int /= Bool" false
    (Cssolver.unify s (con Types.TInt) (con Types.TBool))

let test_unify_binds () =
  let s = Cssolver.empty () in
  Alcotest.(check bool) "$T0 == Int binds" true (Cssolver.unify s (v 0) (con Types.TInt));
  Alcotest.check ty "and resolves to it" (con Types.TInt) (Cssolver.resolve s (v 0));
  (* a variable already bound is not re-bound: it is compared through its binding *)
  Alcotest.(check bool) "$T0 == Double now fails" false
    (Cssolver.unify s (v 0) (con Types.TDouble));
  Alcotest.(check bool) "$T0 == Int still holds" true
    (Cssolver.unify s (v 0) (con Types.TInt))

let test_unify_chains () =
  let s = Cssolver.empty () in
  Alcotest.(check bool) "$T0 == $T1" true (Cssolver.unify s (v 0) (v 1));
  Alcotest.(check bool) "$T1 == String" true (Cssolver.unify s (v 1) (con Types.TString));
  (* resolve follows the chain to its end — the whole reason it is not a plain lookup *)
  Alcotest.check ty "$T0 resolves through $T1" (con Types.TString) (Cssolver.resolve s (v 0));
  Alcotest.(check bool) "a variable unifies with itself" true (Cssolver.unify s (v 0) (v 0))

let test_unify_trails () =
  (* every binding must be undoable, or a wrong guess poisons every later one *)
  let s = Cssolver.empty () in
  let entry = Cssolver.scope_of s in
  ignore (Cssolver.unify s (v 0) (con Types.TInt));
  ignore (Cssolver.unify s (v 1) (con Types.TBool));
  Cssolver.restore s entry;
  Alcotest.check ty "$T0 is open again" (v 0) (Cssolver.resolve s (v 0));
  Alcotest.check ty "$T1 too" (v 1) (Cssolver.resolve s (v 1))

(* --- TODO(41b): simplify ------------------------------------------------------------ *)

let test_simplify_equalities () =
  let s = Cssolver.empty () in
  match
    Cssolver.simplify s
      [ Constraints.Equal (v 0, con Types.TInt, sp);
        Constraints.Equal (v 1, v 0, sp) ]
  with
  | None -> Alcotest.fail "a satisfiable system was rejected"
  | Some kept ->
      Alcotest.(check int) "nothing is left over" 0 (List.length kept);
      Alcotest.check ty "$T1 followed $T0" (con Types.TInt) (Cssolver.resolve s (v 1))

let test_simplify_contradiction () =
  let s = Cssolver.empty () in
  Alcotest.(check bool) "Int and Bool cannot both hold" true
    (Cssolver.simplify s
       [ Constraints.Equal (v 0, con Types.TInt, sp);
         Constraints.Equal (v 0, con Types.TBool, sp) ]
     = None)

let test_simplify_keeps_open_literals () =
  let s = Cssolver.empty () in
  match Cssolver.simplify s [ Constraints.Literal (v 0, Constraints.Int_literal, sp) ] with
  | None -> Alcotest.fail "an open literal constraint is not a contradiction"
  | Some kept ->
      (* it must be KEPT: nothing has decided it yet, and the default is only applied when
         the search finishes. Dropping it here is how `let s: String = 1` gets accepted. *)
      Alcotest.(check int) "the literal constraint is handed back" 1 (List.length kept)

let test_simplify_checks_bound_literals () =
  let s = Cssolver.empty () in
  ignore (Cssolver.unify s (v 0) (con Types.TString));
  Alcotest.(check bool) "an Int literal cannot be a String" true
    (Cssolver.simplify s [ Constraints.Literal (v 0, Constraints.Int_literal, sp) ] = None);
  let s2 = Cssolver.empty () in
  ignore (Cssolver.unify s2 (v 0) (con Types.TDouble));
  Alcotest.(check bool) "but it can be a Double" true
    (Cssolver.simplify s2 [ Constraints.Literal (v 0, Constraints.Int_literal, sp) ] <> None)

let test_simplify_defers_disjunctions () =
  let s = Cssolver.empty () in
  let d =
    Constraints.Disjunction
      {
        Constraints.what = "+";
        is_operator = true;
        args = [ v 0; v 1 ];
        result = v 2;
        choices = [ { Constraints.label = "(Int, Int) -> Int"; index = 0; implies = [] } ];
        dspan = sp;
      }
  in
  match Cssolver.simplify s [ d ] with
  | None -> Alcotest.fail "a disjunction is not a contradiction"
  | Some kept ->
      Alcotest.(check int) "it is handed to the search, not decided" 1 (List.length kept)

(* --- the whole thing, through Cssolver.check ----------------------------------------- *)

let checked (src : string) : string list =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  ignore (Cssolver.check p d);
  List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message) (Diagnostics.all d)

let test_accepts () =
  List.iter
    (fun src -> Alcotest.(check (list string)) src [] (checked src))
    [ "let n = 1 + 2\n"; "let d = 1 + 2.0\n"; "let s = \"a\" + \"b\"\n";
      "func f(_ x: Int) -> Int { return x }\nfunc f(_ x: Double) -> Double { return x }\n\
       let a = f(1)\nlet b: Double = f(1)\n" ]

let test_return_type_overload () =
  (* the case a bidirectional checker cannot reach: both calls are written `g()` *)
  let src =
    "func g() -> Int { return 1 }\nfunc g() -> Double { return 2.5 }\n\
     let c: Double = g()\nlet d: Int = g()\n"
  in
  Alcotest.(check (list string)) "accepted" [] (checked src)

let () =
  Alcotest.run "solver-units"
    [
      ( "unify",
        [
          Alcotest.test_case "concrete types" `Quick test_unify_concrete;
          Alcotest.test_case "binding a variable" `Quick test_unify_binds;
          Alcotest.test_case "chains, and resolve" `Quick test_unify_chains;
          Alcotest.test_case "every binding is undoable" `Quick test_unify_trails;
        ] );
      ( "simplify",
        [
          Alcotest.test_case "equalities propagate" `Quick test_simplify_equalities;
          Alcotest.test_case "contradictions are found" `Quick test_simplify_contradiction;
          Alcotest.test_case "an open literal is kept" `Quick
            test_simplify_keeps_open_literals;
          Alcotest.test_case "a bound literal is checked" `Quick
            test_simplify_checks_bound_literals;
          Alcotest.test_case "a disjunction is deferred" `Quick
            test_simplify_defers_disjunctions;
        ] );
      ( "end to end",
        [
          Alcotest.test_case "well-typed programs" `Quick test_accepts;
          Alcotest.test_case "overloaded on the return type" `Quick
            test_return_type_overload;
        ] );
    ]
