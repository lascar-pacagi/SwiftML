(* Tests for the §6 EXERCISES of concept 03.

   Same convention as concepts 01 and 02: these run under `make lab`, but each group
   first probes whether you have STARTED that exercise. An untouched `check` reports the
   group as skipped (green); the moment your sema behaves differently from the stock one,
   the real assertions switch on — including for a half-finished attempt, which fails
   rather than being silently skipped.

     make lab       C=phase1-minimal/03-sema     concept + exercises
     make exercises C=phase1-minimal/03-sema     just this file

   Both exercises are self-contained in `sema.ml`: nothing here sends you back to the
   parser for a new AST node or to `diagnostics.ml` for a new severity. *)

let diags_of (src : string) : Diagnostics.t list =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Diagnostics.all d

let msgs_at (sev : Diagnostics.severity) (src : string) : string list =
  diags_of src
  |> List.filter (fun (x : Diagnostics.t) -> x.Diagnostics.severity = sev)
  |> List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message)

let errors = msgs_at Diagnostics.Error
let notes = msgs_at Diagnostics.Note

(* --- Exercise 1: reject redeclaration --------------------------------------------
   swiftc:  redecl.swift:2:5: error: invalid redeclaration of 'x'
   A second `let x` (or `var x`) in the same scope is an error, not shadowing. *)
let redecl = "let x = 1\nlet x = 2\nprint(x)\n"
let ex1_started () = List.exists (fun m -> m <> "") (errors redecl)

let test_ex1_redeclaration () =
  Alcotest.(check (list string))
    "a second declaration of the same name is rejected"
    [ "invalid redeclaration of 'x'" ] (errors redecl);
  Alcotest.(check (list string))
    "`var` after `let` is a redeclaration too"
    [ "invalid redeclaration of 'y'" ] (errors "let y = 1\nvar y = 2\nprint(y)\n");
  Alcotest.(check (list string))
    "...and so is `let` after `var`"
    [ "invalid redeclaration of 'z'" ] (errors "var z = 1\nlet z = 2\nprint(z)\n");
  (* the control: distinct names are still fine, and so is REASSIGNING a var *)
  Alcotest.(check (list string))
    "distinct names are not a redeclaration" []
    (errors "let a = 1\nlet b = 2\nvar c = 3\nc = c + a + b\nprint(c)\n");
  (* the walk keeps going: the initializer of the bad declaration is still checked *)
  let both = errors "let w = 1\nlet w = q\n" in
  Alcotest.(check bool) "the redeclaration is reported" true
    (List.mem "invalid redeclaration of 'w'" both);
  Alcotest.(check bool) "and its initializer is still checked" true
    (List.mem "cannot find 'q' in scope" both)

(* --- Exercise 2: swiftc's note on the immutability error --------------------------
   swiftc:  c1.swift:2:1: error: cannot assign to value: 'k' is a 'let' constant
            c1.swift:1:1: note: change 'let' to 'var' to make it mutable
   The error you already emit; the note is new, and it must point at the DECLARATION. *)
let letassign = "let k = 1\nk = 2\n"
let ex2_started () = notes letassign <> []

let test_ex2_note () =
  Alcotest.(check (list string))
    "the note uses swiftc's wording"
    [ "change 'let' to 'var' to make it mutable" ]
    (notes letassign);
  (* it is a NOTE, not a second error: the error count must not change *)
  Alcotest.(check (list string))
    "the error is unchanged"
    [ "cannot assign to value: 'k' is a 'let' constant" ]
    (errors letassign);
  (* and it points at the declaration (line 1), not at the assignment (line 2) *)
  let note =
    List.find
      (fun (x : Diagnostics.t) -> x.Diagnostics.severity = Diagnostics.Note)
      (diags_of letassign)
  in
  Alcotest.(check int) "the note is on the declaration's line" 1
    note.Diagnostics.span.Token.lo.Token.line;
  (* no note where there is nothing to point at, or nothing wrong *)
  Alcotest.(check (list string)) "a var assignment is clean" [] (notes "var v = 1\nv = 2\n");
  Alcotest.(check (list string)) "an undeclared target has no declaration to note" []
    (notes "u = 1\n");
  (* a second offence against the same constant notes it again *)
  Alcotest.(check int) "one note per rejected assignment" 2
    (List.length (notes "let k = 1\nk = 2\nk = 3\n"))

let skip what () =
  Printf.printf "    (%s not started — this group activates as soon as it is)\n%!" what

let group name started what test =
  ( name,
    [
      (if started () then Alcotest.test_case "checked" `Quick test
       else Alcotest.test_case ("skipped — " ^ what ^ " not started") `Quick (skip what));
    ] )

let () =
  Alcotest.run "sema exercises"
    [
      group "ex1 redeclaration" ex1_started "the redeclaration check" test_ex1_redeclaration;
      group "ex2 mutability note" ex2_started "the 'change let to var' note" test_ex2_note;
    ]
