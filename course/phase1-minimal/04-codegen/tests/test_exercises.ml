(* Tests for the §6 EXERCISES of concept 04.

   Same convention as concepts 01–03: these run under `make lab`, but each group first
   probes whether you have STARTED that exercise. An untouched IRGen reports the group as
   skipped (green); the moment your lowering behaves differently from the stock one, the
   real assertions switch on — including for a half-finished attempt, which fails rather
   than being silently skipped.

     make lab       C=phase1-minimal/04-codegen     concept + exercises
     make exercises C=phase1-minimal/04-codegen     just this file

   Note what exercise 2 does to the CONCEPT's suite: constant folding removes the very
   instructions `tests/test_irgen.ml`'s `arithmetic` group counts, so those cases go red
   when it works. That is not a regression — the tests describe a lowering, and you
   changed the lowering. The contract below is the new one. *)

let diags () = Diagnostics.create ()

let parse (src : string) : Ast.program =
  let d = diags () in
  Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d)

(* The instructions a program lowers to, taken from the whole module: exercise 1 needs a
   pre-pass over the program (which names are reassigned?), and that lives in `emit_llvm`,
   so these must not bypass it by folding `emit_stmt` themselves. *)
let is_wrapper (l : string) : bool =
  l = "" || l = "}" || l = "entry:" || l = "ret i32 0"
  || (String.length l > 0 && (l.[0] = ';' || l.[0] = '@'))
  || (String.length l >= 7 && String.sub l 0 7 = "declare")
  || (String.length l >= 6 && String.sub l 0 6 = "define")

let instrs (src : string) : string list =
  String.split_on_char '\n' (Irgen.emit_llvm (parse src))
  |> List.map String.trim
  |> List.filter (fun l -> not (is_wrapper l))

let expr_instrs (src : string) : string list * string =
  let d = diags () in
  let e = Parser.parse_expr (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  let c = Irgen.create () in
  let operand = Irgen.emit_expr c e in
  ( String.split_on_char '\n' (Buffer.contents c.Irgen.buf)
    |> List.map String.trim
    |> List.filter (fun l -> l <> ""),
    operand )

let contains haystack needle =
  let n = String.length haystack and m = String.length needle in
  let rec go i = i + m <= n && (String.sub haystack i m = needle || go (i + 1)) in
  m = 0 || go 0

let n_with needle ls = List.length (List.filter (fun l -> contains l needle) ls)

(* --- Exercise 1: a slot only for what is actually assigned ----------------------------- *)
let ex1_started () =
  match instrs "let x = 5\nprint(x)" with
  | exception _ -> false
  | ls -> n_with "alloca" ls = 0

let test_ex1_no_slot () =
  (* a let bound to a literal disappears entirely: its operand IS the literal *)
  let ls = instrs "let x = 5\nprint(x)" in
  Alcotest.(check int) "no alloca" 0 (n_with "alloca" ls);
  Alcotest.(check int) "no store" 0 (n_with "store" ls);
  Alcotest.(check int) "no load" 0 (n_with "load" ls);
  Alcotest.(check (list string)) "the literal is passed straight to printf"
    [ "%t1 = call i32 (ptr, ...) @printf(ptr @.fmt, i64 5)" ] ls;
  (* A computed initializer is evaluated once and its register reused at every use. The
     value has to be one no constant folder could reduce — every literal in Phase 1 is
     known at compile time, so if you also did exercise 3, `let y = 2 * 3` is just `6`.
     A reassigned var is the one source of a genuinely runtime value. *)
  let ls = instrs "var v = 1\nv = v + 1\nlet y = v * 3\nprint(y + y)" in
  Alcotest.(check int) "one multiply, for the let's initializer" 1 (n_with "= mul i64" ls);
  Alcotest.(check int) "only the var allocates" 1 (n_with "alloca" ls);
  (* both operands of the add are the SAME register: y was computed once *)
  let same_operands (l : string) : bool =
    match String.split_on_char ',' l with
    | [ lhs; rhs ] -> (
        match List.rev (String.split_on_char ' ' (String.trim lhs)) with
        | first_operand :: _ -> String.trim rhs = first_operand
        | [] -> false)
    | _ -> false
  in
  Alcotest.(check bool) "the multiply's register is used for both uses of y" true
    (List.exists (fun l -> contains l "= add i64 %" && same_operands l) ls);
  (* a var that IS reassigned keeps its slot — the exercise must not break mutation *)
  let ls = instrs "var v = 1\nv = v + 1\nprint(v)" in
  Alcotest.(check int) "a reassigned var still gets one slot" 1 (n_with "alloca" ls);
  Alcotest.(check int) "...and is stored twice" 2 (n_with "store i64" ls);
  (* mixed: the assigned var keeps its slot, the let does not get one *)
  let ls = instrs "let k = 7\nvar v = 1\nv = v + k\nprint(v)" in
  Alcotest.(check int) "only the assigned var allocates" 1 (n_with "alloca" ls);
  (* a `var` the program never assigns to needs no slot either — that is the half that
     requires looking at the whole program before lowering it *)
  Alcotest.(check int) "an unassigned var needs no slot" 0
    (n_with "alloca" (instrs "var w = 9\nprint(w)"));
  Alcotest.(check int) "...while an assigned one still does" 1
    (n_with "alloca" (instrs "var w = 9\nw = 10\nprint(w)"))

(* --- Exercise 2: fold constant arithmetic ------------------------------------------ *)
let ex3_started () =
  match expr_instrs "2 * 3" with exception _ -> false | ls, _ -> ls = []

let test_ex3_folding () =
  let folds src expected =
    let ls, operand = expr_instrs src in
    Alcotest.(check (list string)) (Printf.sprintf "%S emits nothing" src) [] ls;
    Alcotest.(check string) (Printf.sprintf "%S folds to %S" src expected) expected operand
  in
  folds "2 * 3" "6";
  folds "1 + 2" "3";
  folds "10 - 4" "6";
  folds "9 / 3" "3";
  folds "9 % 4" "1";
  (* nested folding: the whole tree collapses to one operand *)
  folds "1 + 2 * 3 - 4" "3";
  (* Swift's integer division truncates toward zero, and the remainder follows the
     dividend's sign — fold the way the machine would, or -O and -O0 disagree *)
  folds "-7 / 2" "-3";
  folds "-7 % 2" "-1";
  (* division by zero must NOT be folded: it has to trap at run time, not in the compiler *)
  let ls, _ = expr_instrs "1 / 0" in
  Alcotest.(check int) "1 / 0 still emits an sdiv" 1 (n_with "= sdiv i64" ls);
  let ls, _ = expr_instrs "1 % 0" in
  Alcotest.(check int) "1 %% 0 still emits an srem" 1 (n_with "= srem i64" ls);
  (* A non-constant operand blocks the fold. Note the reassignment: if you also did
     exercise 1, a `var` that is never assigned to becomes an operand like any literal,
     and `v * 2` folds after all. Every assertion here has to hold whether or not the
     other exercise is done. *)
  let ls = instrs "var v = 1\nv = v + 1\nprint(v * 2)" in
  Alcotest.(check int) "a loaded value is not folded" 1 (n_with "= mul i64" ls)

let skip what () =
  Printf.printf "    (%s not started — this group activates as soon as it is)\n%!" what

let group name started what test =
  ( name,
    [
      (if started () then Alcotest.test_case "checked" `Quick test
       else Alcotest.test_case ("skipped — " ^ what ^ " not started") `Quick (skip what));
    ] )

let () =
  Alcotest.run "irgen exercises"
    [
      group "ex1 slots only where assigned" ex1_started "slot-skipping" test_ex1_no_slot;
      group "ex2 constant folding" ex3_started "constant folding" test_ex3_folding;
    ]
