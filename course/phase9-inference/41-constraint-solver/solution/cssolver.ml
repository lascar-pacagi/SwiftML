(* FROZEN SOLUTION — concept 41 `cssolver.ml`. Verified answer key.
   Kept out of the build by `(dirs :standard \ solution)`. Run it with
   `make check-solution C=phase9-inference/41-constraint-solver`.

   Take the system `csgen.ml` wrote down and find an assignment of type variables that
   satisfies it. Mirrors swift/lib/Sema/CSSolver.cpp and CSStep.cpp: a substitution with a
   trail, simplification of everything decidable, then a depth-first search over the
   disjunctions with a scope per guess, a score to rank the solutions, and a hard budget. *)

(* --- the substitution (ConstraintSystem.h's type-variable bindings) ------------------- *)

type solution = {
  bindings : (int, Constraints.ty) Hashtbl.t;
  (* the variables bound so far, most recent first. A scope is a position in this list, so
     undoing a guess costs only what the guess added. swiftc calls it the trail, and
     gives it a whole header: swift/include/swift/Sema/CSTrail.h. *)
  mutable trail : int list;
  (* which variables a literal constraint applies to, and of which kind: needed to default
     anything still unbound when the search ends, and to score one solution against
     another *)
  literals : (int, Constraints.literal_kind) Hashtbl.t;
}

let empty () : solution =
  { bindings = Hashtbl.create 64; trail = []; literals = Hashtbl.create 64 }

let rec resolve (s : solution) (t : Constraints.ty) : Constraints.ty =
  match t with
  | Constraints.Con _ -> t
  | Constraints.Var n -> (
      match Hashtbl.find_opt s.bindings n with None -> t | Some t' -> resolve s t')

(* The types a literal of each kind may take, most preferred FIRST — the head is the
literal's
   DEFAULT type. Swift declares these in the standard library rather than the compiler:
   `public typealias IntegerLiteralType = Int` in stdlib/public/core/Policy.swift. *)
let literal_types = function
  | Constraints.Int_literal -> [ Types.TInt; Types.TDouble ]
  | Constraints.Double_literal -> [ Types.TDouble ]

(* --- scopes (ConstraintSystem.h:1323, `struct SolverScope`) ------------------------------
   Trying an overload makes bindings that may have to be undone. Remember where the trail
   was on entry; undo back to it on the way out. That is what makes a wrong guess cheap,
   and it is why the search can afford to be exhaustive. *)

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

(* --- TODO(41a): unify ----------------------------------------------------------------- *)
let unify (s : solution) (a : Constraints.ty) (b : Constraints.ty) : bool =
  match (resolve s a, resolve s b) with
  | Constraints.Con x, Constraints.Con y -> Types.equal x y
  | Constraints.Var n, other | other, Constraints.Var n -> (
      match other with
      | Constraints.Var m when m = n -> true (* already the same variable *)
      | _ ->
          Hashtbl.replace s.bindings n other;
          s.trail <- n :: s.trail;
          true)

(* --- TODO(41b): simplify -------------------------------------------------------------- *)
let rec simplify (s : solution) (cs : Constraints.t list) : Constraints.t list option =
  match cs with
  | [] -> Some []
  | Constraints.Equal (a, b, _) :: rest ->
      if unify s a b then simplify s rest else None
  | (Constraints.Literal (t, kind, _) as c) :: rest -> (
      match resolve s t with
      | Constraints.Var _ -> (
          (* still unknown — keep it; the default is applied when the search finishes *)
          match simplify s rest with None -> None | Some kept -> Some (c :: kept))
      | Constraints.Con concrete ->
          if List.exists (Types.equal concrete) (literal_types kind) then simplify s rest
          else None)
  | (Constraints.Disjunction _ as d) :: rest -> (
      (* a choice cannot be made by looking at it — hand it to the search *)
      match simplify s rest with None -> None | Some kept -> Some (d :: kept))

(* --- the score (Score.h, `SK_NonDefaultLiteral` at :59) ----------------------------------
   Several assignments can satisfy the same system, and the checker has to pick one. swiftc
   ranks them on a dozen axes; one is enough here, and it is one of theirs: a literal
   that had to leave its default type counts against a solution. That single rule is why
   `1 + 2` is Int arithmetic even though Double arithmetic satisfies every constraint
   just as well. *)
let score (s : solution) : int =
  Hashtbl.fold
    (fun n kind acc ->
      match (kind, resolve s (Constraints.Var n)) with
      | Constraints.Int_literal, Constraints.Con Types.TDouble -> acc + 1
      | _ -> acc)
    s.literals 0

(* --- TODO(41c): the search (CSStep.cpp's DisjunctionStep) ----------------------------- *)
let rec solve (search : search) (s : solution) (cs : Constraints.t list) :
    (solution * int) option =
  search.scopes_explored <- search.scopes_explored + 1;
  if search.scopes_explored > scope_budget then raise Too_complex;
  match simplify s cs with
  | None -> None
  | Some remaining -> (
      match
        List.partition (function Constraints.Disjunction _ -> true | _ -> false) remaining
      with
      | [], _ ->
          (* nothing left to choose, so this is a solution. A snapshot, because the caller
             will undo these bindings before trying the next alternative.

             DEFAULTS ARE NOT APPLIED HERE. A variable still unbound is one nothing has
             pinned, and `solve_system` gives it its default type once every component has
             had its say — doing it here would default variables belonging to components
             that have not been solved yet, and `let b: Double = f(1)` would be rejected
             because the literal was made an Int before the annotation was ever read. *)
          let final = { s with bindings = Hashtbl.copy s.bindings } in
          (* a literal constraint that was still open when it was met is KEPT, and this is
             where it is finally answered: `let s: String = 1` binds the variable to String
             through the annotation long after the literal constraint went by, and nothing
             would ever have looked at it again. *)
          let literals_hold =
            List.for_all
              (function
                | Constraints.Literal (t, kind, _) -> (
                    match resolve final t with
                    | Constraints.Con c -> List.exists (Types.equal c) (literal_types kind)
                    | Constraints.Var _ -> true)
                | _ -> true)
              remaining
          in
          if literals_hold then Some (final, score final) else None
      | Constraints.Disjunction d :: other_disjunctions, simple ->
          let rest = other_disjunctions @ simple in
          let best = ref None in
          List.iter
            (fun (c : Constraints.choice) ->
              let entry = scope_of s in
              (match solve search s (c.Constraints.implies @ rest) with
              | None -> ()
              | Some (candidate, candidate_score) -> (
                  (* keep the BEST, not the first: taking the first success would be enough
                     to answer yes or no, but the score is what makes `1 + 2` an Int *)
                  match !best with
                  | Some (_, best_score) when best_score <= candidate_score -> ()
                  | _ -> best := Some (candidate, candidate_score)));
              restore s entry)
            d.Constraints.choices;
          !best
      | _ :: _, _ -> None)

(* --- the splitter, TODO(41e) (CSStep.h:232, `SplitterStep`) ------------------------------
   The single most important thing the real solver does for performance, and the reason an
   ordinary Swift file compiles at all. Constraints that share no type variable cannot
   affect each other, so solving them together multiplies two searches that could have
   been added. Split the system into connected components of the constraint graph, solve
   each alone, and put the answers back together — k^(m+n) becomes k^m + k^n. *)

let rec vars_of (c : Constraints.t) : int list =
  let of_ty = function Constraints.Var n -> [ n ] | Constraints.Con _ -> [] in
  match c with
  | Constraints.Equal (a, b, _) -> of_ty a @ of_ty b
  | Constraints.Literal (a, _, _) -> of_ty a
  | Constraints.Disjunction d ->
      List.concat_map
        (fun (ch : Constraints.choice) -> List.concat_map vars_of ch.Constraints.implies)
        d.Constraints.choices

let components (cs : Constraints.t list) : Constraints.t list list =
  (* union-find over type variables; two constraints join a component when they mention a
     variable in common. This is swiftc's ConstraintGraph, in the form this subset needs. *)
  let parent = Hashtbl.create 64 in
  let rec find v =
    match Hashtbl.find_opt parent v with
    | None -> v
    | Some p when p = v -> v
    | Some p ->
        let r = find p in
        Hashtbl.replace parent v r;
        r
  in
  let union a b =
    let ra = find a and rb = find b in
    if ra <> rb then Hashtbl.replace parent ra rb
  in
  List.iter
    (fun c ->
      match vars_of c with
      | [] -> ()
      | v :: rest ->
          if not (Hashtbl.mem parent v) then Hashtbl.replace parent v v;
          List.iter
            (fun w ->
              if not (Hashtbl.mem parent w) then Hashtbl.replace parent w w;
              union v w)
            rest)
    cs;
  let buckets = Hashtbl.create 16 in
  let ungrouped = ref [] in
  List.iter
    (fun c ->
      match vars_of c with
      | [] -> ungrouped := c :: !ungrouped
      | v :: _ ->
          let r = find v in
          Hashtbl.replace buckets r (c :: Option.value ~default:[] (Hashtbl.find_opt
          buckets r)))
    cs;
  let grouped = Hashtbl.fold (fun _ v acc -> List.rev v :: acc) buckets [] in
  match !ungrouped with [] -> grouped | u -> List.rev u :: grouped

let solve_system (search : search) (s : solution) (cs : Constraints.t list) :
    (solution * int) option =
  let default_the_rest () =
    (* every literal nobody pinned takes its default type — `IntegerLiteralType = Int` *)
    Hashtbl.iter
      (fun n kind ->
        match resolve s (Constraints.Var n) with
        | Constraints.Var m ->
            Hashtbl.replace s.bindings m (Constraints.Con (List.hd (literal_types kind)))
        | Constraints.Con _ -> ())
      s.literals
  in
  let rec go acc_score = function
    | [] ->
        default_the_rest ();
        Some (s, acc_score)
    | component :: rest -> (
        match solve search s component with
        | None -> None
        | Some (part, part_score) ->
            (* components share no variables, so merging is a union — no conflict is
            possible *) Hashtbl.iter (fun k v -> Hashtbl.replace s.bindings k v)
            part.bindings; go (acc_score + part_score) rest)
  in
  go 0 (components cs)

(* --- diagnosing a FAILED search (given)
---------------------------------------------------
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
       type someone WROTE. Drop each written type in turn and solve what is left: if the
       rest of the program has an answer, that answer is what the annotation disagrees
       with, and naming both is swiftc's wording. Dropping a constraint to see what the
       others say is the same move as swiftc's "fixes", in the one case this subset
       needs. *)
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

(* --- the entry point (given) ---------------------------------------------------------- *)

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
      | Constraints.Literal (Constraints.Var n, kind, _) -> Hashtbl.replace s.literals n
      kind
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
