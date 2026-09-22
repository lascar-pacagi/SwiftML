(* FROZEN SOLUTION — concept 41 `csapply.ml`. Verified answer key.

   The solver's answer lives in a table of type variables. Every later stage wants it ON the
   tree, so one final walk rebuilds the program as a `Tast` with each node's type filled in
   and each overloaded name replaced by the declaration that was chosen.

   This is concept 05's lesson arriving from the other direction. There, `check_expr` wrote
   the flex into the operand as it went, because the decision and the walk were the same
   thing. Here they are two passes — the solver decides, this walk records — which is exactly
   why swiftc needs a file for it.

   Design oracle: swift/lib/Sema/CSApply.cpp — `ExprRewriter`, which walks the expression
   "resulting in a fully-type-checked expression" (its own words), calling `Expr::setType` and
   replacing each overloaded reference with a `ConcreteDeclRef` naming the chosen decl. *)

type solution = (int, Constraints.ty) Hashtbl.t

let solution_of (bindings : (int, Constraints.ty) Hashtbl.t) : solution = bindings

let rec resolve (s : solution) (t : Constraints.ty) : Constraints.ty =
  match t with
  | Constraints.Con _ -> t
  | Constraints.Var n -> (
      match Hashtbl.find_opt s n with None -> t | Some t' -> resolve s t')

(* The type the solver gave this node. A node with no entry never had a variable — it was
   concrete the moment it was generated. *)
let type_of (g : Csgen.t) (s : solution) (span : Token.span) : Types.ty =
  match Hashtbl.find_opt g.Csgen.types_of span with
  | None -> Types.TInt
  | Some t -> (
      match resolve s t with Constraints.Con c -> c | Constraints.Var _ -> Types.TInt)

let rec expr (g : Csgen.t) (s : solution) (expression : Ast.expr) : Tast.expr =
  let span = Ast.expr_span expression in
  let mk e = { Tast.e; ty = type_of g s span; span } in
  match expression with
  | Ast.Int_lit (n, _) -> mk (Tast.Int_lit n)
  | Ast.Double_lit (f, _) -> mk (Tast.Double_lit f)
  | Ast.Bool_lit (b, _) -> mk (Tast.Bool_lit b)
  | Ast.String_lit (str, _) -> mk (Tast.String_lit str)
  | Ast.Var (x, _) -> mk (Tast.Local x)
  | Ast.Unary (op, e0, _) -> mk (Tast.Unary (op, expr g s e0))
  | Ast.Binary (op, l, r, _) -> mk (Tast.Binary (op, expr g s l, expr g s r))
  | Ast.Ascribe (e0, _, _) -> mk (Tast.Coerce (expr g s e0))
  | Ast.Call ("print", [ a ], _) -> mk (Tast.Print (expr g s a))
  | Ast.Call ("print", _, _) -> mk (Tast.Print (mk (Tast.Int_lit 0)))
  | Ast.Call (f, args, _) ->
      (* the index the solver settled on. Without it the tree would still say "a call to
         something named f", which is exactly the question this concept exists to answer. *)
      let chosen = Option.value ~default:0 (Hashtbl.find_opt g.Csgen.chosen span) in
      mk (Tast.Fn_call (f, chosen, List.map (expr g s) args))

let rec stmt (g : Csgen.t) (s : solution) (st : Ast.stmt) : Tast.stmt =
  match st with
  | Ast.Let { name; is_var; value; span; _ } ->
      Tast.Let { name; is_var; value = expr g s value; span }
  | Ast.Assign { name; value; span } -> Tast.Assign { name; value = expr g s value; span }
  | Ast.Expr_stmt (e, _) -> Tast.Expr_stmt (expr g s e)
  | Ast.If { cond; then_blk; else_blk; span } ->
      Tast.If
        {
          cond = expr g s cond;
          then_blk = List.map (stmt g s) then_blk;
          else_blk = Option.map (List.map (stmt g s)) else_blk;
          span;
        }
  | Ast.While { cond; body; span } ->
      Tast.While { cond = expr g s cond; body = List.map (stmt g s) body; span }
  | Ast.For { var; lo; hi; body; span } ->
      Tast.For
        { var; lo = expr g s lo; hi = expr g s hi; body = List.map (stmt g s) body; span }
  | Ast.Break span -> Tast.Break span
  | Ast.Continue span -> Tast.Continue span
  | Ast.Return (v, span) -> Tast.Return (Option.map (expr g s) v, span)

let func (g : Csgen.t) (s : solution) (f : Ast.func_decl) : Tast.func_decl =
  let sg = Csgen.signature_of g f in
  {
    Tast.fname = f.Ast.fname;
    params =
      List.map2
        (fun (p : Ast.param) t -> { Tast.pname = p.Ast.pname; pty = t })
        f.Ast.params sg.Constraints.params;
    ret = sg.Constraints.result;
    body = List.map (stmt g s) f.Ast.body;
    fspan = f.Ast.fspan;
  }

let program (g : Csgen.t) (s : solution) (p : Ast.program) : Tast.program =
  {
    Tast.items =
      List.map
        (function
          | Ast.IFunc f -> Tast.IFunc (func g s f)
          | Ast.IStmt st -> Tast.IStmt (stmt g s st))
        p.Ast.items;
  }
