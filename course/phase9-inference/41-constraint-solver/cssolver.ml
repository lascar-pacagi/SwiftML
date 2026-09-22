(* The SOLVER. You implement the TODO(41a-d) holes.

   Take the system `csgen.ml` wrote down and find an assignment of type variables that
   satisfies it. Mirrors swift/lib/Sema/CSSolver.cpp and CSStep.cpp: a substitution with a
   trail, simplification of everything decidable, then a depth-first search over the
   disjunctions with a scope per guess, a score to rank the solutions, and a hard budget. *)

(* --- the substitution (ConstraintSystem.h's type-variable bindings) ---------------------- *)

type solution = {
  bindings : (int, Constraints.ty) Hashtbl.t;
  (* the variables bound so far, most recent first. A scope is a position in this list, so
     undoing a guess costs only what the guess added. swiftc calls it the trail, and gives it
     a whole header: swift/include/swift/Sema/CSTrail.h. *)
  mutable trail : int list;
  (* which variables a literal constraint applies to, and of which kind: needed to default
     anything still unbound when the search ends, and to score one solution against another *)
  literals : (int, Constraints.literal_kind) Hashtbl.t;
}

let empty () : solution =
  { bindings = Hashtbl.create 64; trail = []; literals = Hashtbl.create 64 }

let rec resolve (s : solution) (t : Constraints.ty) : Constraints.ty =
  match t with
  | Constraints.Con _ -> t
  | Constraints.Var n -> (
      match Hashtbl.find_opt s.bindings n with None -> t | Some t' -> resolve s t')

(* The types a literal of each kind may take, most preferred FIRST — the head is the literal's
   DEFAULT type. Swift declares these in the standard library rather than the compiler:
   `public typealias IntegerLiteralType = Int` in stdlib/public/core/Policy.swift. *)
let literal_types = function
  | Constraints.Int_literal -> [ Types.TInt; Types.TDouble ]
  | Constraints.Double_literal -> [ Types.TDouble ]

(* --- scopes (ConstraintSystem.h:1323, `struct SolverScope`) ------------------------------
   Trying an overload makes bindings that may have to be undone. Remember where the trail was
   on entry; undo back to it on the way out. That is what makes a wrong guess cheap, and it is
   why the search can afford to be exhaustive. *)

type scope = int list

let scope_of (s : solution) : scope = s.trail

let restore (s : solution) (entry : scope) : unit =
  let rec undo () =
    if s.trail != entry then
      match s.trail with
      | [] -> ()
      | v :: rest ->
          Hashtbl.remove s.bindings v;
          s.trail <- rest;
          undo ()
  in
  undo ()

(* --- the budget (LangOptions.h:959-969) --------------------------------------------------
   The search is exponential in the worst case, so it gets a hard limit and REPORTS rather
   than hangs. swiftc has four of these — an expression timeout, a memory ceiling, a scope
   count and a trail size — and the diagnostic they raise is the one everyone has seen. *)

exception Too_complex

let scope_budget = 20_000

type search = { mutable scopes_explored : int }

(* TODO(41a): make two types equal under the current solution, or say they cannot be.
   Resolve both first — what matters is what they are NOW, not what they were written as.
   Two concrete types must agree. A variable takes the other side, and every binding you
   make must be pushed on the trail, or a scope cannot undo it. §3.1. *)
let unify (s : solution) (a : Constraints.ty) (b : Constraints.ty) : bool =
  ignore (s, a, b, resolve);
  failwith "TODO(41a): unify"

(* TODO(41b): solve everything that can be solved WITHOUT GUESSING, and hand back what is
   left. [None] means the system is contradictory. Three kinds arrive here and they are not
   alike: an equality is work for [unify]; a literal constraint can be checked once its type
   is known and must be KEPT while it is not, because the default is only applied when the
   search finishes; a disjunction can never be decided by looking at it. §3.2. *)
let rec simplify (s : solution) (cs : Constraints.t list) : Constraints.t list option =
  ignore (s, cs, unify, literal_types, simplify);
  failwith "TODO(41b): simplify"

(* --- the score (Score.h, `SK_NonDefaultLiteral` at :59) ----------------------------------
   Several assignments can satisfy the same system, and the checker has to pick one. swiftc
   ranks them on a dozen axes; one is enough here, and it is one of theirs: a literal that had
   to leave its default type counts against a solution. That single rule is why `1 + 2` is Int
   arithmetic even though Double arithmetic satisfies every constraint just as well. *)
let score (s : solution) : int =
  Hashtbl.fold
    (fun n kind acc ->
      match (kind, resolve s (Constraints.Var n)) with
      | Constraints.Int_literal, Constraints.Con Types.TDouble -> acc + 1
      | _ -> acc)
    s.literals 0

(* TODO(41c): the search (swiftc's CSStep.cpp, `DisjunctionStep`).

   Simplify first. If nothing is left to choose, every literal still unbound takes its
   default type and you have a solution — score it and return it. Otherwise take one
   disjunction and try each alternative IN ITS OWN SCOPE, undoing the bindings it made
   before trying the next.

   Mind the literal constraints [simplify] handed back: they were open when it met them, and
   this is the only place left to answer them. `let s: String = 1` binds the variable through
   the annotation long after the literal constraint went by, and if nothing looks again, the
   program is accepted.

   Two details decide whether this is a type checker or a toy. Keep the BEST-scoring
   solution rather than the first that works — the first is enough to answer yes or no, the
   best is what makes `1 + 2` Int arithmetic rather than Double. And count the scopes you
   enter: the search is exponential in the worst case, so raise [Too_complex] once the
   budget is gone instead of running until someone kills the compiler. §3.3. *)
let rec solve (search : search) (s : solution) (cs : Constraints.t list) :
    (solution * int) option =
  ignore (search, s, cs, simplify, score, scope_of, restore, literal_types, solve);
  failwith "TODO(41c): solve"

(* --- TODO(41d): the splitter (CSStep.h:232, `SplitterStep`) ------------------------------
   The single most important thing the real solver does for performance, and the reason an
   ordinary Swift file compiles at all. Constraints that share no type variable cannot affect
   each other, so solving them together multiplies two searches that could have been added.
   Split the system into connected components of the constraint graph, solve each alone, and
   put the answers back together — k^(m+n) becomes k^m + k^n. *)

(* given: every type variable a constraint mentions, including the ones buried in the
   alternatives of a disjunction *)
let rec vars_of (c : Constraints.t) : int list =
  let of_ty = function Constraints.Var n -> [ n ] | Constraints.Con _ -> [] in
  match c with
  | Constraints.Equal (a, b, _) -> of_ty a @ of_ty b
  | Constraints.Literal (a, _, _) -> of_ty a
  | Constraints.Disjunction d ->
      List.concat_map
        (fun (ch : Constraints.choice) -> List.concat_map vars_of ch.Constraints.implies)
        d.Constraints.choices

(* The SPLITTER — an optional second rung, like concept 01's fast lexer and concept 34's
   register allocators. `[ cs ]` below is CORRECT: one group, everything solved together,
   and every test in this concept passes with it. It is also the difference between a
   compiler and a toy, and §5 measures exactly that — fifteen independent one-line
   statements are enough to exhaust the budget above, because solving them together
   MULTIPLIES fifteen two-way choices instead of adding them.

   TODO(41e), when you want it: two constraints can only affect each other if they mention a
   type variable in common, directly or through a chain of other constraints. Group them by
   that relation — union-find over the variables is the usual shape — and solve each group
   alone. Constraints that mention no variable at all can go anywhere. `tests/test_split.ml`
   stays quiet until you start, then checks both the grouping and the speed. §3.4. *)
let components (cs : Constraints.t list) : Constraints.t list list =
  ignore vars_of;
  [ cs ]

let solve_system (search : search) (s : solution) (cs : Constraints.t list) :
    (solution * int) option =
  let rec go acc_score = function
    | [] -> Some (s, acc_score)
    | component :: rest -> (
        match solve search s component with
        | None -> None
        | Some (part, part_score) ->
            (* components share no variables, so merging is a union — no conflict is possible *)
            Hashtbl.iter (fun k v -> Hashtbl.replace s.bindings k v) part.bindings;
            go (acc_score + part_score) rest)
  in
  go 0 (components cs)

(* --- diagnosing a FAILED search (given) ---------------------------------------------------
   The hard part of any constraint solver, and the reason swiftc has a directory for it
   (lib/Sema/CSDiagnostics.cpp, ~9000 lines). When the search comes back empty you know the
   system has no solution — and nothing else. Not which constraint is to blame, because the
   solver never committed to one; not which operand is wrong, because it tried both ways.

   swiftc recovers the blame by solving AGAIN with "fixes" enabled: a fix lets a failing
   constraint succeed at a score penalty, so the search completes, and the fixes it had to
   apply are the diagnosis. Here is the crude version — find the first overload set where no
   alternative survives on its own, and report it the way concept 05 would have, from the
   operand types the disjunction carries. §6 exercise 3 is the swiftc route. *)
let diagnose (search : search) (diagnostics : Diagnostics.sink) (s : solution)
    (cs : Constraints.t list) : bool =
  (* the literal constraints alone: what an operand can be, before anything outside asks *)
  let literal_only =
    List.filter (function Constraints.Literal _ -> true | _ -> false) cs
  in
  ignore (simplify s literal_only);
  let reported = ref false in
  List.iter
    (fun c ->
      match c with
      | Constraints.Disjunction d when not !reported ->
          let viable =
            List.exists
              (fun (ch : Constraints.choice) ->
                let entry = scope_of s in
                (* against the operand constraints, NOT the whole system. A disjunction is
                   only to blame if nothing it offers fits what its operands are — if the
                   conflict is with something further out, say an annotation, blaming the
                   operator says something false: `+` really can add two Ints. *)
                let ok = simplify s (ch.Constraints.implies @ literal_only) <> None in
                restore s entry;
                ok)
              d.Constraints.choices
          in
          if not viable then (
            reported := true;
            (* for the MESSAGE only, a variable still open is shown at its default type:
               the reader wrote `1`, and being told the operand is `_` helps nobody *)
            let shown =
              List.map
                (fun a ->
                  match resolve s a with
                  | Constraints.Con t -> Types.string_of_ty t
                  | Constraints.Var n -> (
                      match Hashtbl.find_opt s.literals n with
                      | Some kind -> Types.string_of_ty (List.hd (literal_types kind))
                      | None -> "_"))
                d.Constraints.args
            in
            Diagnostics.error diagnostics d.Constraints.dspan
              (match (d.Constraints.is_operator, shown) with
              (* concept 05's two operator wordings, and swiftc's, chosen the same way *)
              | true, [ a; b ] when a = b ->
                  Printf.sprintf
                    "binary operator '%s' cannot be applied to two '%s' operands"
                    d.Constraints.what a
              | true, [ a; b ] ->
                  Printf.sprintf
                    "binary operator '%s' cannot be applied to operands of type '%s' and \
                     '%s'"
                    d.Constraints.what a b
              | true, [ a ] ->
                  Printf.sprintf
                    "unary operator '%s' cannot be applied to an operand of type '%s'"
                    d.Constraints.what a
              (* a CALL is a different shape, and swiftc words it differently. Its `abs` and
                 `min` are generic rather than overloaded, so it reaches for the conformance
                 wording ("requires that 'String' conform to 'SignedNumeric'"); ours are an
                 overload set, and this is what swiftc says when a genuine overload set has
                 no match. The modelling difference is §2's, not a bug. *)
              | false, _ ->
                  Printf.sprintf "no exact matches in call to global function '%s'"
                    d.Constraints.what
              | true, _ ->
                  Printf.sprintf "operator '%s' cannot be applied to these operands"
                    d.Constraints.what))
      | _ -> ())
    cs;
  if !reported then true
  else
    (* Nothing offered by any overload set is wrong in itself, so the conflict comes from a
       type someone WROTE. Drop each written type in turn and solve what is left: if the rest
       of the program has an answer, that answer is what the annotation disagrees with, and
       naming both is swiftc's wording. Dropping a constraint to see what the others say is
       the same move as swiftc's "fixes", in the one case this subset needs. *)
    let written =
      List.filter
        (function Constraints.Equal (_, Constraints.Con _, _) -> true | _ -> false)
        cs
    in
    List.exists
      (fun c ->
        match c with
        | Constraints.Equal (a, Constraints.Con wanted, span) ->
            let others = List.filter (fun c' -> c' != c) cs in
            let probe = empty () in
            Hashtbl.iter (fun k v -> Hashtbl.replace probe.literals k v) s.literals;
            (match solve search probe others with
            | Some (sol, _) -> (
                match resolve sol a with
                | Constraints.Con got when not (Types.equal got wanted) ->
                    Diagnostics.error diagnostics span
                      (Printf.sprintf
                         "cannot convert value of type '%s' to specified type '%s'"
                         (Types.string_of_ty got) (Types.string_of_ty wanted));
                    true
                | _ -> false)
            | None -> false)
        | _ -> false)
      written

(* --- the entry point (given) ------------------------------------------------------------- *)

let span_of_program (program : Ast.program) : Token.span =
  match program.Ast.items with
  | Ast.IStmt (Ast.Let { span; _ }) :: _
  | Ast.IStmt (Ast.Assign { span; _ }) :: _
  | Ast.IStmt (Ast.Expr_stmt (_, span)) :: _ ->
      span
  | Ast.IFunc { fspan; _ } :: _ -> fspan
  | _ -> Token.dummy_span

let check (program : Ast.program) (diagnostics : Diagnostics.sink) : Tast.program option =
  let g = Csgen.create diagnostics in
  Csgen.generate_program g program;
  let s = empty () in
  List.iter
    (function
      | Constraints.Literal (Constraints.Var n, kind, _) -> Hashtbl.replace s.literals n kind
      | _ -> ())
    g.Csgen.constraints;
  let search = { scopes_explored = 0 } in
  let outcome =
    try solve_system search s g.Csgen.constraints
    with Too_complex ->
      Diagnostics.error diagnostics (span_of_program program)
        "the compiler is unable to type-check this expression in reasonable time; try \
         breaking up the expression into distinct sub-expressions";
      None
  in
  match outcome with
  | None ->
      if not (Diagnostics.has_errors diagnostics) then
        if
          not
            (let fresh_state = empty () in
             Hashtbl.iter (fun k v -> Hashtbl.replace fresh_state.literals k v) s.literals;
             diagnose { scopes_explored = 0 } diagnostics fresh_state g.Csgen.constraints)
        then
          (* no single overload set is to blame — the system is unsatisfiable as a whole,
             which is what swiftc means by this message *)
          Diagnostics.error diagnostics (span_of_program program)
            "type of expression is ambiguous without a type annotation";
      None
  | Some (sol, _) ->
      if Diagnostics.has_errors diagnostics then None
      else (
        (* record which alternative each disjunction settled on, so csapply can name it *)
        List.iter
          (function
            | Constraints.Disjunction d ->
                List.iter
                  (fun (ch : Constraints.choice) ->
                    if
                      List.for_all
                        (function
                          | Constraints.Equal (a, b, _) -> (
                              match (resolve sol a, resolve sol b) with
                              | Constraints.Con x, Constraints.Con y -> Types.equal x y
                              | _ -> false)
                          | _ -> true)
                        ch.Constraints.implies
                    then
                      if not (Hashtbl.mem g.Csgen.chosen d.Constraints.dspan) then
                        Hashtbl.replace g.Csgen.chosen d.Constraints.dspan
                          ch.Constraints.index)
                  d.Constraints.choices
            | _ -> ())
          g.Csgen.constraints;
        Some (Csapply.program g (Csapply.solution_of sol.bindings) program))
