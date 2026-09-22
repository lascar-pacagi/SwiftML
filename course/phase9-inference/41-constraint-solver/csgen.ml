(* Constraint GENERATION — a *contract* (fully written). One walk over the AST that allocates
   a type variable per expression and writes down what must hold. It decides nothing.

   Read it next to concept 05's `infer` and concept 07's. The shapes line up arm for arm, and
   every place those asked a question and committed to an answer, this one states a
   requirement and moves on:

     05 / 07                                   41
     infer (Int_lit n) = TInt                  fresh $T, Literal ($T, Int_literal)
     unify l tl r tr -> flex or fail           Disjunction over the operator's overloads
     Hashtbl.find functions f -> the signature  Disjunction over EVERY declaration named f
     check_expr e t  -> push t down            Equal ($T_e, Con t)

   The payoff is not that this is shorter — it is that NOTHING here looks at a result. There
   is no order in which the facts must be discovered, so an annotation eight lines below can
   settle a call eight lines above.

   Design oracle: swift/lib/Sema/CSGen.cpp — `ConstraintGenerator::visit*`, one method per
   expression kind, each allocating type variables and calling `CS.addConstraint`. Its
   `visitDeclRefExpr` builds exactly the disjunction below: one choice per declaration the
   name could refer to. *)

type t = {
  mutable next_var : int;
  mutable constraints : Constraints.t list;
  (* every expression's type variable, keyed by its span — the solution is written back onto
     the tree through this map, which is what CSApply does with `Expr::setType` *)
  types_of : (Token.span, Constraints.ty) Hashtbl.t;
  (* and which overload each CALL settled on, keyed the same way *)
  chosen : (Token.span, int) Hashtbl.t;
  environment : (string, Constraints.ty * bool) Hashtbl.t;
  (* name -> every declaration with that name, in source order. The list IS the overload set,
     and its length is the width of the disjunction a call to it generates. *)
  functions : (string, Constraints.signature list) Hashtbl.t;
  mutable current_return : Types.ty option;
  diagnostics : Diagnostics.sink;
}

let create (diagnostics : Diagnostics.sink) : t =
  {
    next_var = 0;
    constraints = [];
    types_of = Hashtbl.create 64;
    chosen = Hashtbl.create 16;
    environment = Hashtbl.create 16;
    functions = Hashtbl.create 16;
    current_return = None;
    diagnostics;
  }

let fresh (g : t) : Constraints.ty =
  let v = Constraints.Var g.next_var in
  g.next_var <- g.next_var + 1;
  v

let emit (g : t) (c : Constraints.t) : unit = g.constraints <- c :: g.constraints

let record (g : t) (span : Token.span) (ty : Constraints.ty) : Constraints.ty =
  Hashtbl.replace g.types_of span ty;
  ty

let error (g : t) span msg = Diagnostics.error g.diagnostics span msg

let resolve_ty (g : t) (span : Token.span) (name : string) : Types.ty =
  match Types.of_name name with
  | Some t -> t
  | None ->
      error g span (Printf.sprintf "cannot find type '%s' in scope" name);
      Types.TInt

(* An overload set becomes a DISJUNCTION: one alternative per signature, each asserting that
   the arguments and the result have that signature's types. A set with one member is not a
   choice at all, so it is emitted as plain equalities — worth doing, because it is the
   difference between a search and none, and `--emit-constraints` shows which you got. *)
(* [sigs] carries each signature WITH the index of the declaration it came from. The index
   is not the position in this list: arity filtering may have dropped some, and the tree has
   to name the declaration the reader wrote, not the one the solver happened to try third. *)
let apply_overloads (g : t) ?(is_operator = false) (what : string)
    (sigs : (int * Constraints.signature) list) (args : Constraints.ty list)
    (result : Constraints.ty) (span : Token.span) : unit =
  let constraints_for (s : Constraints.signature) =
    Constraints.Equal (result, Constraints.Con s.Constraints.result, span)
    :: List.map2
         (fun a p -> Constraints.Equal (a, Constraints.Con p, span))
         args s.Constraints.params
  in
  match sigs with
  | [ (i, only) ] ->
      (* one candidate is not a choice: no disjunction, and the answer is known here — so
         record it now, because the solver will never be asked and csapply still needs it *)
      Hashtbl.replace g.chosen span i;
      List.iter (emit g) (constraints_for only)
  | _ ->
      emit g
        (Constraints.Disjunction
           {
             Constraints.what;
             is_operator;
             args;
             result;
             choices =
               List.map
                 (fun (i, s) ->
                   {
                     Constraints.label = Constraints.show_signature s;
                     index = i;
                     implies = constraints_for s;
                   })
                 sigs;
             dspan = span;
           })

let rec generate (g : t) (expression : Ast.expr) : Constraints.ty =
  let span = Ast.expr_span expression in
  match expression with
  | Ast.Int_lit _ ->
      let v = fresh g in
      emit g (Constraints.Literal (v, Constraints.Int_literal, span));
      record g span v
  | Ast.Double_lit _ ->
      let v = fresh g in
      emit g (Constraints.Literal (v, Constraints.Double_literal, span));
      record g span v
  | Ast.Bool_lit _ -> record g span (Constraints.Con Types.TBool)
  | Ast.String_lit _ -> record g span (Constraints.Con Types.TString)
  | Ast.Var (x, _) -> (
      match Hashtbl.find_opt g.environment x with
      | Some (t, _) -> record g span t
      | None ->
          error g span (Printf.sprintf "cannot find '%s' in scope" x);
          record g span (fresh g))
  | Ast.Unary (Ast.Neg, e0, _) ->
      let a = generate g e0 in
      let v = fresh g in
      apply_overloads g ~is_operator:true "-"
        [ (0, { Constraints.params = [ Types.TInt ]; result = Types.TInt });
          (1, { Constraints.params = [ Types.TDouble ]; result = Types.TDouble }) ]
        [ a ] v span;
      record g span v
  | Ast.Binary (op, l, r, _) ->
      let a = generate g l in
      let b = generate g r in
      let v = fresh g in
      apply_overloads g ~is_operator:true (Ast.string_of_binop op)
        (List.mapi (fun i s -> (i, s)) (Constraints.operator_overloads op))
        [ a; b ] v span;
      record g span v
  | Ast.Ascribe (e0, tyname, _) ->
      let a = generate g e0 in
      let t = resolve_ty g span tyname in
      emit g (Constraints.Equal (a, Constraints.Con t, span));
      record g span (Constraints.Con t)
  | Ast.Call ("print", args, _) -> (
      match args with
      | [ a ] ->
          ignore (generate g a);
          record g span (Constraints.Con Types.TVoid)
      | _ ->
          error g span "print(_:) expects exactly one argument";
          List.iter (fun a -> ignore (generate g a)) args;
          record g span (Constraints.Con Types.TVoid))
  | Ast.Call (f, args, _) -> (
      match Hashtbl.find_opt g.functions f with
      | None ->
          error g span (Printf.sprintf "cannot find '%s' in scope" f);
          List.iter (fun a -> ignore (generate g a)) args;
          record g span (fresh g)
      | Some sigs -> (
          (* only the declarations whose ARITY matches can apply. Swift filters the same way
             before it builds the disjunction — an alternative that cannot possibly hold is
             not a choice, it is noise in the search. *)
          let n = List.length args in
          match
            List.filteri (fun _ _ -> true) (List.mapi (fun i s -> (i, s)) sigs)
            |> List.filter (fun (_, s) -> List.length s.Constraints.params = n)
          with
          | [] ->
              error g span
                (Printf.sprintf "no exact matches in call to global function '%s'" f);
              List.iter (fun a -> ignore (generate g a)) args;
              record g span (fresh g)
          | viable ->
              let ats = List.map (generate g) args in
              let v = fresh g in
              apply_overloads g f viable ats v span;
              record g span v))

let rec generate_stmt (g : t) (s : Ast.stmt) : unit =
  match s with
  | Ast.Let { name; is_var; annot; value; span } ->
      let v = generate g value in
      (match annot with
      | None -> ()
      | Some tyname ->
          (* at the VALUE's span: this is a claim about the value, and that is where swiftc
             puts the caret when it turns out to be wrong *)
          emit g
            (Constraints.Equal
               (v, Constraints.Con (resolve_ty g span tyname), Ast.expr_span value)));
      Hashtbl.replace g.environment name (v, is_var)
  | Ast.Assign { name; value; span } -> (
      let v = generate g value in
      match Hashtbl.find_opt g.environment name with
      | None -> error g span (Printf.sprintf "cannot find '%s' in scope" name)
      | Some (t, is_var) ->
          if not is_var then
            error g span
              (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant" name);
          emit g (Constraints.Equal (v, t, Ast.expr_span value)))
  | Ast.Expr_stmt (expression, _) -> ignore (generate g expression)
  | Ast.If { cond; then_blk; else_blk; _ } ->
      emit g (Constraints.Equal (generate g cond, Constraints.Con Types.TBool,
                                 Ast.expr_span cond));
      generate_block g then_blk;
      Option.iter (generate_block g) else_blk
  | Ast.While { cond; body; _ } ->
      emit g (Constraints.Equal (generate g cond, Constraints.Con Types.TBool,
                                 Ast.expr_span cond));
      generate_block g body
  | Ast.For { var; lo; hi; body; _ } ->
      emit g (Constraints.Equal (generate g lo, Constraints.Con Types.TInt,
                                 Ast.expr_span lo));
      emit g (Constraints.Equal (generate g hi, Constraints.Con Types.TInt,
                                 Ast.expr_span hi));
      let saved = Hashtbl.copy g.environment in
      Hashtbl.replace g.environment var (Constraints.Con Types.TInt, false);
      generate_block g body;
      Hashtbl.reset g.environment;
      Hashtbl.iter (Hashtbl.replace g.environment) saved
  | Ast.Break _ | Ast.Continue _ -> ()
  | Ast.Return (value, span) -> (
      match (value, g.current_return) with
      | None, _ -> ()
      | Some e, Some rt ->
          emit g (Constraints.Equal (generate g e, Constraints.Con rt, Ast.expr_span e))
      | Some e, None ->
          ignore (generate g e);
          error g span "return invalid outside of a func")

and generate_block (g : t) (body : Ast.stmt list) : unit =
  (* a block is a scope: what it binds is gone at the `}` — concept 06's rule, unchanged *)
  let saved = Hashtbl.copy g.environment in
  List.iter (generate_stmt g) body;
  Hashtbl.reset g.environment;
  Hashtbl.iter (Hashtbl.replace g.environment) saved

let signature_of (g : t) (f : Ast.func_decl) : Constraints.signature =
  {
    Constraints.params =
      List.map (fun (p : Ast.param) -> resolve_ty g f.Ast.fspan p.Ast.ptype) f.Ast.params;
    result =
      (match f.Ast.ret with None -> Types.TVoid | Some n -> resolve_ty g f.Ast.fspan n);
  }

let generate_program (g : t) (program : Ast.program) : unit =
  (* PASS 1 — collect the overload sets, so a call can be generated before the declaration it
     resolves to has been read. Concept 07 did the same walk to get ONE signature per name;
     the only change is that a second declaration extends the set instead of being an error. *)
  List.iter
    (function
      | Ast.IFunc f ->
          let s = signature_of g f in
          let existing = Option.value ~default:[] (Hashtbl.find_opt g.functions f.Ast.fname) in
          if List.exists (Constraints.same_signature s) existing then
            error g f.Ast.fspan
              (Printf.sprintf "invalid redeclaration of '%s'" f.Ast.fname)
          else Hashtbl.replace g.functions f.Ast.fname (existing @ [ s ])
      | Ast.IStmt _ -> ())
    program.Ast.items;
  (* PASS 2 — the bodies and the top-level statements. *)
  List.iter
    (function
      | Ast.IFunc f ->
          let saved = Hashtbl.copy g.environment in
          let s = signature_of g f in
          List.iter2
            (fun (p : Ast.param) t ->
              Hashtbl.replace g.environment p.Ast.pname (Constraints.Con t, false))
            f.Ast.params s.Constraints.params;
          g.current_return <- Some s.Constraints.result;
          List.iter (generate_stmt g) f.Ast.body;
          g.current_return <- None;
          Hashtbl.reset g.environment;
          Hashtbl.iter (Hashtbl.replace g.environment) saved
      | Ast.IStmt s -> generate_stmt g s)
    program.Ast.items;
  g.constraints <- List.rev g.constraints
