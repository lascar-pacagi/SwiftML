(* Tests for the §6 EXERCISES of concept 02.

   Same convention as concept 01: these run under `make lab`, but each group first probes
   whether you have STARTED that exercise. An untouched parser reports the group as skipped
   (green); the moment your parser behaves differently from the stock one, the real
   assertions switch on — including for a half-finished attempt, which fails rather than
   being silently skipped.

     make lab       C=phase1-minimal/02-parser     concept + exercises
     make exercises C=phase1-minimal/02-parser     just this file

   Both exercises are self-contained in `parser.ml` — nothing here sends you back to
   concept 01 to add a token, or to `ast.ml` to add a constructor. *)

let mk_d (src : string) : Parser.t * Diagnostics.sink =
  let diags = Diagnostics.create () in
  (Parser.create (Lexer.tokenize (Lexer.create src diags)) diags, diags)

let msgs_of_program (src : string) : string list =
  let p, d = mk_d src in
  ignore (Parser.parse_program p);
  List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message) (Diagnostics.all d)

let contains (needle : string) (s : string) : bool =
  let n = String.length needle and l = String.length s in
  let rec go i = i + n <= l && (String.sub s i n = needle || go (i + 1)) in
  go 0

(* --- Exercise 1: a good prefix error, and recovery -------------------------------
   Two halves. (a) name the offending token instead of a bare "expected expression".
   (b) recover: skip to the next Newline after a broken statement, so ONE run reports one
   error per broken line and still parses the good ones. Measured on the shipped parser,
   the fixture below produces SIX diagnostics — a cascade, because without recovery the
   parser stumbles token by token. With the exercise done it produces two. *)
let fixture = "1 +\nx === 5\nprint(2)\n"

let ex1_started () =
  match msgs_of_program fixture with
  | exception Failure _ -> false
  | ms -> List.exists (contains "found") ms

let test_ex1_recovery () =
  let p, d = mk_d fixture in
  let prog = Parser.parse_program p in
  let ms = List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message) (Diagnostics.all d) in
  Alcotest.(check bool) "a message names the offending token" true
    (List.exists (contains "found") ms);
  Alcotest.(check bool) "one error per broken line, not a cascade" true
    (List.length ms >= 1 && List.length ms <= 3);
  (* and the good statement on the third line still made it into the program *)
  let has_print =
    List.exists
      (fun (s : Ast.stmt) ->
        match s with Ast.Expr_stmt (Ast.Call ("print", _, _), _) -> true | _ -> false)
      prog.Ast.stmts
  in
  Alcotest.(check bool) "parsing recovered and kept the good statement" true has_print

(* --- Exercise 2: right-associative `**` ------------------------------------------
   Done inside parser.ml: two ADJACENT `*` tokens are the operator (the spans say whether
   they touch), it binds above `*`, it recurses at its own bp rather than bp + 1, and it
   desugars to the call `pow(a, b)` rather than growing the AST. *)
(* The NAME you desugar to is yours — `pow`, `power`, whatever reads right — and if you
   took the token route instead (a StarStar token and a Pow binop) that works too. This
   printer normalises either shape to a single spelling, so the assertions below are about
   PRECEDENCE and ASSOCIATIVITY, which is what the exercise is really testing. *)
let power_names = [ "pow"; "power"; "powi"; "ipow"; "expt"; "exponent" ]

let rec norm (e : Ast.expr) : string =
  match e with
  | Ast.Int_lit (n, _) -> string_of_int n
  | Ast.Binary (op, l, r, _) ->
      Printf.sprintf "(%s %s %s)" (Ast.string_of_binop op) (norm l) (norm r)
  | Ast.Call (f, [ a; b ], _) when List.mem f power_names ->
      Printf.sprintf "(** %s %s)" (norm a) (norm b)
  | e -> Ast.dump_expr e

let dump_expr_of (src : string) : string = norm (Parser.parse_expr (fst (mk_d src)))

let ex2_started () =
  let p, d = mk_d "2 ** 3" in
  match Parser.parse_expr p with
  | exception Failure _ -> false
  | _ -> Diagnostics.all d = []

let ndiags_expr (src : string) : int =
  let p, d = mk_d src in
  ignore (Parser.parse_expr p);
  List.length (Diagnostics.all d)

let test_ex2_power () =
  Alcotest.(check string) "** is RIGHT associative" "(** 2 (** 3 2))" (dump_expr_of "2 ** 3 ** 2");
  Alcotest.(check string) "** binds tighter than *" "(* (** 2 3) 4)" (dump_expr_of "2 ** 3 * 4");
  Alcotest.(check string) "...and tighter than +" "(+ 1 (** 2 3))" (dump_expr_of "1 + 2 ** 3");
  (* a single star still means multiplication *)
  Alcotest.(check string) "one star is unchanged" "(* 2 3)" (dump_expr_of "2 * 3");
  (* and two stars that are NOT adjacent are not the operator *)
  Alcotest.(check bool) "`2 * * 3` is still an error" true (ndiags_expr "2 * * 3" >= 1)

let skip what () =
  Printf.printf "    (%s not started — this group activates as soon as it is)\n%!" what

let group name started what test =
  ( name,
    [
      (if started () then Alcotest.test_case "checked" `Quick test
       else Alcotest.test_case ("skipped — " ^ what ^ " not started") `Quick (skip what));
    ] )

let () =
  Alcotest.run "parser exercises"
    [
      group "ex1 prefix error + recovery" ex1_started "the improved prefix error"
        test_ex1_recovery;
      group "ex2 right-associative **" ex2_started "the ** operator" test_ex2_power;
    ]
