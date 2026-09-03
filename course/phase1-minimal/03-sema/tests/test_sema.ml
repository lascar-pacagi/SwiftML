(* Alcotest unit tests for sema (concept 03).

   These run the front end (lex → parse → sema) in-process and assert the *exact*
   diagnostic messages, their source locations, their order and their count — stronger
   than the cram test, which only greps a substring of one message.

   The suite is deliberately exercise-NEUTRAL: it filters to Error-severity diagnostics
   and never feeds a program that redeclares a name, so §6's exercises (redeclaration,
   notes) can be done or not done without any of this turning red.

   RED until you implement `sema.ml : check`; GREEN against `solution/sema.ml`. *)

let front_end (src : string) : Diagnostics.sink =
  let diags = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src diags)) diags) in
  Sema.check p diags;
  diags

let sema_errors (src : string) : string list =
  Diagnostics.all (front_end src)
  |> List.filter (fun (d : Diagnostics.t) -> d.Diagnostics.severity = Diagnostics.Error)
  |> List.map (fun (d : Diagnostics.t) -> d.Diagnostics.message)

(* every error as "line:col: message" — the spans matter as much as the wording, because
   they are what the driver prints and what an editor would underline *)
let sema_located (src : string) : string list =
  Diagnostics.all (front_end src)
  |> List.filter (fun (d : Diagnostics.t) -> d.Diagnostics.severity = Diagnostics.Error)
  |> List.map (fun (d : Diagnostics.t) ->
         Printf.sprintf "%d:%d: %s" d.Diagnostics.span.Token.lo.Token.line
           d.Diagnostics.span.Token.lo.Token.col d.Diagnostics.message)

let has_error src msg =
  Alcotest.(check bool)
    (Printf.sprintf "%S reports %S" src msg)
    true
    (List.mem msg (sema_errors src))

let accepted src =
  Alcotest.(check (list string)) (Printf.sprintf "%S is accepted" src) [] (sema_errors src)

let n_errors src n =
  Alcotest.(check int) (Printf.sprintf "%S reports %d error(s)" src n) n
    (List.length (sema_errors src))

(* --- valid programs ---------------------------------------------------------------
   The control half of the suite. A checker that rejects too much is as broken as one
   that rejects too little, and these cover every expression and statement form the
   Phase-1 grammar can produce. *)
let test_accept () =
  accepted "let a = 2\nvar c = a + 1\nc = c * a\nprint(c)";
  accepted "var v = 1\nv = 2";
  accepted "let x = 1\nlet y = x + x\nprint(y)";
  (* every operator in one expression, and unary minus *)
  accepted "let a = 1 + 2 - 3 * 4 / 5 % 6\nprint(-a)";
  (* nesting: parens, unary applied to a parenthesised binary, calls in expressions *)
  accepted "let a = 2\nprint(-(a * (a + 1)) % 7)";
  (* a let may be READ freely — only assigning to it is an error *)
  accepted "let k = 5\nvar v = k\nv = v + k\nprint(v * k)";
  (* a var reassigned repeatedly, including from itself *)
  accepted "var i = 0\ni = i + 1\ni = i * i\ni = -i\nprint(i)";
  (* bare expression statements are checked but not required to do anything *)
  accepted "let a = 1\na + 1\nprint(a)";
  (* nothing to check at all *)
  accepted "";
  accepted "\n\n// only a comment\n\n";
  Alcotest.(check bool) "a valid program leaves has_errors false" false
    (Diagnostics.has_errors (front_end "let a = 1\nprint(a)"))

(* --- name resolution --------------------------------------------------------------
   An unknown name must be caught WHEREVER it appears, which is really a test that
   check_expr recurses into every constructor rather than stopping at the top. *)
let test_undeclared () =
  has_error "print(y)" "cannot find 'y' in scope";
  has_error "x = 5" "cannot find 'x' in scope";
  (* one per expression form: unary, both sides of a binary, deep nesting *)
  has_error "print(-y)" "cannot find 'y' in scope";
  has_error "print(1 + y)" "cannot find 'y' in scope";
  has_error "print(y + 1)" "cannot find 'y' in scope";
  has_error "let a = 1\nprint(-(a * (a + y)) % 2)" "cannot find 'y' in scope";
  (* and in each statement position: initializer, assignment source, bare expression *)
  has_error "let a = y" "cannot find 'y' in scope";
  has_error "var v = 1\nv = y" "cannot find 'y' in scope";
  has_error "y + 1" "cannot find 'y' in scope";
  has_error "print(y)" "cannot find 'y' in scope"

let test_declaration_order () =
  (* a name is in scope only AFTER its declaration *)
  has_error "let a = a" "cannot find 'a' in scope";
  has_error "var a = a" "cannot find 'a' in scope";
  has_error "print(z)\nlet z = 1" "cannot find 'z' in scope";
  has_error "v = 1\nvar v = 2" "cannot find 'v' in scope";
  (* ...and the very next statement can already use it *)
  accepted "let a = 1\nprint(a)";
  accepted "var b = 1\nb = b + 1\nprint(b)";
  (* the initializer sees the PREVIOUS binding of a different name, not itself *)
  accepted "let a = 1\nlet b = a + 1\nprint(b)"

(* --- mutability ------------------------------------------------------------------- *)
let test_immutability () =
  has_error "let k = 1\nk = 2" "cannot assign to value: 'k' is a 'let' constant";
  (* the same constant assigned twice reports twice: one diagnostic per offence *)
  n_errors "let k = 1\nk = 2\nk = 3" 2;
  (* a var in the same position is fine *)
  accepted "var v = 1\nv = 2";
  (* the target must exist AND be mutable — an undeclared target is the other message *)
  has_error "u = 1" "cannot find 'u' in scope";
  Alcotest.(check (list string))
    "an undeclared target is not ALSO reported as a constant" [ "cannot find 'u' in scope" ]
    (sema_errors "u = 1")

(* an assignment has two halves and BOTH are checked: the target must be a declared
   var, and the right-hand side is an expression like any other *)
let test_assign_rhs () =
  has_error "var v = 1\nv = w" "cannot find 'w' in scope";
  has_error "let k = 1\nk = w" "cannot find 'w' in scope";
  has_error "var v = 1\nv = v + z" "cannot find 'z' in scope";
  (* both halves can fail at once *)
  n_errors "let k = 1\nk = w" 2;
  accepted "var v = 1\nlet a = 2\nv = v + a"

(* --- calls ------------------------------------------------------------------------ *)
let test_print_arity () =
  has_error "print(1, 2)" "print(_:) expects exactly one argument";
  has_error "print()" "print(_:) expects exactly one argument";
  has_error "print(1, 2, 3)" "print(_:) expects exactly one argument";
  n_errors "print(1, 2)" 1;
  accepted "print(1)";
  accepted "let a = 1\nprint(a * 2)"

(* the only callable in Phase 1 is print(_:); anything else is an unknown name — the
   same message swiftc gives for a call to an undefined function *)
let test_unknown_callee () =
  has_error "foo(1)" "cannot find 'foo' in scope";
  has_error "let a = 1\nbar(a)" "cannot find 'bar' in scope";
  has_error "foo()" "cannot find 'foo' in scope";
  (* a declared VARIABLE is still not callable *)
  has_error "let f = 1\nf(2)" "cannot find 'f' in scope";
  (* the call is not a print, so the arity rule must not fire as well *)
  n_errors "foo(1, 2)" 1

(* --- recovery: one run reports everything ------------------------------------------
   A checker that stops at the first problem makes the user recompile once per mistake. *)
let test_reports_keep_going () =
  Alcotest.(check (list string))
    "a bad call still reports its arguments"
    [ "print(_:) expects exactly one argument"; "cannot find 'y' in scope" ]
    (sema_errors "print(1, y)");
  Alcotest.(check (list string))
    "an unknown callee still reports its arguments"
    [ "cannot find 'foo' in scope"; "cannot find 'y' in scope" ]
    (sema_errors "foo(y)");
  Alcotest.(check (list string))
    "and later statements are still checked"
    [ "cannot find 'p' in scope"; "cannot find 'q' in scope" ]
    (sema_errors "print(p)\nprint(q)");
  (* every USE of an unknown name is reported, not just the first *)
  n_errors "print(y)\nprint(y)" 2;
  (* an error does not poison the statements after it *)
  n_errors "print(y)\nlet a = 1\nprint(a)" 1;
  (* several problems inside ONE expression, left to right *)
  Alcotest.(check (list string))
    "both operands of a binary are reported"
    [ "cannot find 'p' in scope"; "cannot find 'q' in scope" ]
    (sema_errors "print(p + q)")

(* --- spans -------------------------------------------------------------------------
   The location is half the diagnostic. Every case here was measured against
   `swiftc -typecheck -diagnostic-style=llvm` and matches it column for column, except
   `let a = a`, where swiftc reports a different rule ("circular reference") from the
   declaration — see §2's divergence table. *)
let test_spans () =
  Alcotest.(check (list string)) "the argument of print" [ "1:7: cannot find 'y' in scope" ]
    (sema_located "print(y)");
  Alcotest.(check (list string)) "an assignment target" [ "1:1: cannot find 'x' in scope" ]
    (sema_located "x = 5");
  Alcotest.(check (list string)) "inside a binary" [ "1:11: cannot find 'y' in scope" ]
    (sema_located "print(1 + y)");
  Alcotest.(check (list string)) "under a unary minus" [ "1:8: cannot find 'y' in scope" ]
    (sema_located "print(-y)");
  Alcotest.(check (list string)) "an unknown callee, at the name" [ "1:1: cannot find 'foo' in scope" ]
    (sema_located "foo(1)");
  Alcotest.(check (list string))
    "two errors, in source order, each at its own column"
    [ "1:7: cannot find 'p' in scope"; "1:11: cannot find 'q' in scope" ]
    (sema_located "print(p + q)");
  (* line numbers survive across statements *)
  Alcotest.(check (list string)) "on the third line"
    [ "3:7: cannot find 'y' in scope" ]
    (sema_located "let a = 1\nprint(a)\nprint(y)");
  (* the self-reference points at the USE, not at the declaration *)
  Alcotest.(check (list string)) "the initializer's own name" [ "1:9: cannot find 'a' in scope" ]
    (sema_located "let a = a")

(* --- severity ----------------------------------------------------------------------
   The driver bails on Errors; the concept's own rules are all errors, and every one of
   them must set has_errors so the pipeline stops before IRGen. *)
let test_severity () =
  let d = front_end "print(y)" in
  Alcotest.(check int) "one diagnostic" 1 (List.length (Diagnostics.all d));
  Alcotest.(check bool) "reported as an Error" true
    (List.for_all
       (fun (x : Diagnostics.t) -> x.Diagnostics.severity = Diagnostics.Error)
       (Diagnostics.all d));
  Alcotest.(check bool) "has_errors is true" true (Diagnostics.has_errors d);
  List.iter
    (fun src ->
      Alcotest.(check bool)
        (Printf.sprintf "%S sets has_errors" src)
        true
        (Diagnostics.has_errors (front_end src)))
    [ "print(y)"; "x = 5"; "let k = 1\nk = 2"; "print(1, 2)"; "foo(1)" ]

let () =
  Alcotest.run "sema"
    [
      ("accept", [ Alcotest.test_case "valid programs have no errors" `Quick test_accept ]);
      ( "scope",
        [
          Alcotest.test_case "undeclared names, everywhere" `Quick test_undeclared;
          Alcotest.test_case "bound only after declaration" `Quick
            test_declaration_order;
        ] );
      ( "immutability",
        [
          Alcotest.test_case "assign to a let constant" `Quick test_immutability;
          Alcotest.test_case "the assigned expression is checked" `Quick test_assign_rhs;
        ] );
      ( "calls",
        [
          Alcotest.test_case "print arity" `Quick test_print_arity;
          Alcotest.test_case "unknown callee" `Quick test_unknown_callee;
        ] );
      ("recovery", [ Alcotest.test_case "one run reports every error" `Quick test_reports_keep_going ]);
      ("spans", [ Alcotest.test_case "line:col matches swiftc" `Quick test_spans ]);
      ("severity", [ Alcotest.test_case "errors stop the pipeline" `Quick test_severity ]);
    ]
