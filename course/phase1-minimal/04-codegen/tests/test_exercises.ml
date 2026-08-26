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

(* --- Exercise 1a: a `let`'s value reaches its uses directly ------------------------
   The half that needs no analysis. `let x = 5` binds a name to an operand; every `Var x`
   should hand that operand back, so the literal turns up INSIDE the instruction that uses
   it and no memory is touched at all. This group activates on its own, so you can do the
   `let` half first and see it pass before starting the `var` half below. *)
let ex1a_started () =
  match instrs "let x = 5\nprint(x)" with
  | exception _ -> false
  | ls -> n_with "alloca" ls = 0

let test_ex1a_let_value () =
  (* the literal is substituted into the call — not stored and loaded back *)
  Alcotest.(check (list string)) "the let's value reaches printf directly"
    [ "%t1 = call i32 (ptr, ...) @printf(ptr @.fmt, i64 5)" ] (instrs "let x = 5\nprint(x)");
  (* substitution survives being used in arithmetic, and through another binding *)
  let no_memory src =
    let ls = instrs src in
    Alcotest.(check int)
      (Printf.sprintf "%S touches no memory" src)
      0
      (n_with "alloca" ls + n_with "store" ls + n_with "load" ls)
  in
  no_memory "let a = 2\nlet b = 3\nprint(a * b)";
  no_memory "let a = 5\nlet b = a\nprint(b)";
  no_memory "let a = 1\nlet b = a + a\nlet c = b + b\nprint(c)";
  (* the operand really is the VALUE: printing a let bound to another let still passes 5 *)
  Alcotest.(check bool) "a let bound to a let passes the same operand" true
    (List.exists
       (fun l -> contains l "@printf(ptr @.fmt, i64 5)")
       (instrs "let a = 5\nlet b = a\nprint(b)"));
  (* a computed initializer is evaluated ONCE and its register reused — substitution must
     not duplicate work. Use a value no constant folder can reduce (see exercise 2). *)
  let ls = instrs "var v = 1\nv = v + 1\nlet y = v * 3\nprint(y + y)" in
  Alcotest.(check int) "one multiply, for the let's initializer" 1 (n_with "= mul i64" ls);
  let same_operands (l : string) : bool =
    match String.split_on_char ',' l with
    | [ lhs; rhs ] -> (
        match List.rev (String.split_on_char ' ' (String.trim lhs)) with
        | first_operand :: _ -> String.trim rhs = first_operand
        | [] -> false)
    | _ -> false
  in
  Alcotest.(check bool) "both uses of y are the same register" true
    (List.exists (fun l -> contains l "= add i64 %" && same_operands l) ls);
  (* and the program still says what it said before *)
  Alcotest.(check bool) "the assigned var keeps its slot" true
    (n_with "alloca" ls = 1)

(* --- Exercise 1b: a `var` gets a slot only if something assigns to it ---------------
   The half that needs the pre-pass. Activates separately from 1a. *)
let ex1b_started () =
  match instrs "var w = 9\nprint(w)" with
  | exception _ -> false
  | ls -> n_with "alloca" ls = 0

let test_ex1b_unassigned_var () =
  Alcotest.(check int) "an unassigned var needs no slot" 0
    (n_with "alloca" (instrs "var w = 9\nprint(w)"));
  Alcotest.(check int) "...but an assigned one still does" 1
    (n_with "alloca" (instrs "var w = 9\nw = 10\nprint(w)"));
  (* THE trap. A var assigned LATER must not keep handing out its old value. There is
     more than one right way to avoid it — scan for assignment targets before lowering,
     or drop the name from the map when you lower an assignment — so this checks the
     SEMANTICS rather than the strategy: the two prints must receive different operands.

     `var v = 1; print(v); v = 2; print(v)` prints 1 then 2. An implementation that
     promotes every binding and never invalidates prints 1 twice, with IR that is
     perfectly well-formed — nothing but a check of this shape catches it. *)
  let printf_args (src : string) : string list =
    instrs src
    |> List.filter_map (fun l ->
           if contains l "@printf(ptr @.fmt, i64 " then
             match String.rindex_opt l ' ' with
             | Some i ->
                 let a = String.sub l (i + 1) (String.length l - i - 1) in
                 Some (String.concat "" (String.split_on_char ')' a))
             | None -> None
           else None)
  in
  let args = printf_args "var v = 1\nprint(v)\nv = 2\nprint(v)" in
  Alcotest.(check int) "two prints" 2 (List.length args);
  Alcotest.(check bool) "the two prints do NOT share an operand" true
    (List.nth args 0 <> List.nth args 1);
  (* and after an assignment, the initializer's value is gone for good *)
  Alcotest.(check bool) "a read after the assignment is not the old immediate" true
    (match printf_args "var v = 1\nv = 2\nprint(v)" with [ a ] -> a <> "1" | _ -> false);
  Alcotest.(check bool) "...nor after two of them" true
    (match printf_args "var v = 1\nv = 2\nv = 3\nprint(v)" with
    | [ a ] -> a <> "1" && a <> "2"
    | _ -> false);
  (* mixed program: the let and the untouched var are promoted, the assigned var is not *)
  let ls = instrs "let k = 7\nvar u = 2\nvar v = 1\nv = v + k + u\nprint(v)" in
  Alcotest.(check int) "one slot, for the one assigned name" 1 (n_with "alloca" ls)

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
      group "ex1a let values" ex1a_started "the let half of slot-skipping" test_ex1a_let_value;
      group "ex1b unassigned vars" ex1b_started "the var half of slot-skipping"
        test_ex1b_unassigned_var;
      group "ex2 constant folding" ex3_started "constant folding" test_ex3_folding;
    ]
