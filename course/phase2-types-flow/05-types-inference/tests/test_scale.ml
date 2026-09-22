(* Does checking TERMINATE — and does it stay linear in the size of the program?

   `infer` and `check_expr` call each other, so termination is not obvious from either
   one. The argument is a lexicographic measure on (size of the expression, mode), with
   `check` ordered above `infer`:

     infer e       -> infer e'        e' a STRICT SUBTERM      size decreases
     infer e       -> check_expr e' t e' a STRICT SUBTERM      size decreases
     check_expr e  -> check_expr e'   e' a STRICT SUBTERM      size decreases
     check_expr e  -> infer e         the SAME e               size equal, mode drops

   Every call strictly decreases that pair, and the order is well-founded, so there is no
   infinite chain. The whole argument rests on ONE invariant:

     check_expr may hand its own argument to infer.
     infer NEVER hands its own argument to check_expr — only a strict subterm.

   Break it — write `infer e = check_expr e <some guess>` — and the recursion loops on the
   first expression it meets. The same invariant bounds the COST: each node bounces from
   check to infer at most once, so a well-typed program is walked a constant number of
   times, and checking is linear in its size.

   Neither half is visible in a unit test that types `1 + 2`, so this file states them the
   only way a test can: build programs whose shapes stress each recursion path, make them
   big enough that quadratic and linear are orders of magnitude apart, and require the
   checker to finish. A loop never finishes; a quadratic takes minutes. Sizes are chosen
   so a correct checker uses under a hundredth of the budget — this must never flake, and
   the bug it was written for overruns it five times over.

   One gap it cannot close: a checker that genuinely LOOPS hangs here rather than failing,
   because alcotest has no per-case timeout. `tests/sema-scale.t` runs the same shape under
   `timeout`, which does.

   It measures the ACCEPTED path deliberately. Recovery after an error is the subject of
   §6's exercise 5, which fixes a quadratic of its own; the stock checker still has that
   one, and pinning it here would fail the answer key for a reason the exercise owns. *)

let terms = 80_000

(* CPU seconds, not wall clock: a loaded machine must not turn this red. A correct checker
   takes ~0.04s here; the conjunct-order bug this file was written for took ~15s. *)
let budget = 3.0

let repeat (s : string) (n : int) : string =
  String.concat "" (List.init n (fun _ -> s))

let finishes (what : string) (source : string) () : unit =
  let diagnostics = Diagnostics.create () in
  let started = Sys.time () in
  let program =
    Parser.parse_program
      (Parser.create (Lexer.tokenize (Lexer.create source diagnostics)) diagnostics)
  in
  ignore (Sema.check program diagnostics);
  let elapsed = Sys.time () -. started in
  (* the programs are well-typed: anything reported means the shape stopped exercising
     the path it was built for, and the timing below would be measuring nothing *)
  Alcotest.(check (list string))
    (Printf.sprintf "%s is accepted" what)
    []
    (List.map
       (fun (d : Diagnostics.t) -> d.Diagnostics.message)
       (Diagnostics.all diagnostics));
  if elapsed > budget then
    Alcotest.failf
      "%s: %d terms took %.2fs of CPU, over the %.1fs budget.@.A correct checker walks \
       each node a constant number of times and takes well under 0.1s here, so this is \
       not a slow machine — some rule is re-walking a subtree it has already seen."
      what terms elapsed budget

let () =
  Alcotest.run "sema-scale"
    [
      ( "termination",
        [
          (* the flex succeeds at the top: one big check_expr re-walk under a long infer *)
          Alcotest.test_case "a literal chain flexing to Double" `Quick
            (finishes "1 + 1 + … + 1 + 1.5"
               ("print(1" ^ repeat " + 1" terms ^ " + 1.5)\n"));
          (* the Double comes FIRST, so every level asks unify about a Double-typed spine *)
          Alcotest.test_case "the same chain, Double first" `Quick
            (finishes "1 + 1.5 + 1 + 1 + …"
               ("print(1 + 1.5" ^ repeat " + 1" terms ^ ")\n"));
          (* no infer at all: check_expr descends the whole tree from the annotation *)
          Alcotest.test_case "an annotation pushed down a chain" `Quick
            (finishes "let d: Double = 1 + 1 + … + 1"
               ("let d: Double = 1" ^ repeat " + 1" terms ^ "\n"));
          (* the knot itself: `as` makes infer call check, which falls back to infer, at
             every single level — the one shape that exercises the bounce n times *)
          Alcotest.test_case "infer/check alternating all the way down" `Quick
            (finishes "1 as Double as Double as …"
               ("print(1" ^ repeat " as Double" terms ^ ")\n"));
          (* deep on one side, to catch a rule that recurses twice per level *)
          Alcotest.test_case "deeply nested unary minus" `Quick
            (finishes "-(-(-(… 1 …)))" ("print(" ^ repeat "-" terms ^ "1)\n"));
        ] );
    ]
