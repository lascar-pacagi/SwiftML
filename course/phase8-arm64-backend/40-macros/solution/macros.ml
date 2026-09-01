(* macros.ml — the compile-time macro expander (concept 40).

   A macro is code that writes code: `#line` becomes an integer literal, `#assert(c)` becomes a
   conditional trap. Expansion is an AST -> AST rewrite that runs BEFORE the type checker — so the
   rest of the compiler (sema, SILGen, …) never sees a macro, only the ordinary AST it expanded to.
   This is exactly swiftc's model: macros run early, as a syntactic transform, and everything
   downstream type-checks the expansion.

   The recursive AST walk (reaching every macro wherever it appears) is given; you write the
   expansion RULES — what each macro turns into. *)

let int_lit n span = Ast.Int_lit (n, span)

(* a trap statement: `fatalError()` lowers to a runtime trap (SILGen turns it into Sil.Trap, exit
   133 — like swiftc's failed `assert`/`precondition`) *)
let fatal_error span = Ast.Expr_stmt (Ast.Call ("fatalError", [], span), span)

(* ===== the learner's hole: TODO(40) the macro expansion rules ===== *)

(* expand a macro USED AS AN EXPRESSION — `#line`, `#column` become integer literals. (`args` and
   the already-expanded sub-args are available; v0's expression macros take none.) *)
let expand_macro_expr (name : string) (_args : Ast.expr list) (span : Token.span) : Ast.expr =
  match name with
  | "line" -> int_lit span.Token.lo.Token.line span
  | "column" -> int_lit span.Token.lo.Token.col span
  | other ->
      (* unknown expression macro — leave a marker the type checker will reject *)
      Ast.MacroExpr (other, [], span)

(* expand a macro USED AS A STATEMENT — `#assert(cond)` becomes `if cond { } else { fatalError() }`.
   Return `None` to fall back to expanding it as an expression statement. *)
let expand_macro_stmt (name : string) (args : Ast.expr list) (span : Token.span) : Ast.stmt option =
  match (name, args) with
  | "assert", [ cond ] ->
      Some (Ast.If { cond; then_blk = []; else_blk = Some [ fatal_error span ]; span })
  | _ -> None

(* ===== given: the recursive walk that reaches every macro ===== *)

let rec ex (e : Ast.expr) : Ast.expr =
  match e with
  | Ast.MacroExpr (name, args, span) -> expand_macro_expr name (List.map ex args) span
  | Ast.Int_lit _ | Ast.Double_lit _ | Ast.Bool_lit _ | Ast.String_lit _ | Ast.Var _ | Ast.Nil _ -> e
  | Ast.Unary (op, a, s) -> Ast.Unary (op, ex a, s)
  | Ast.Binary (op, a, b, s) -> Ast.Binary (op, ex a, ex b, s)
  | Ast.Call (f, args, s) -> Ast.Call (f, List.map (fun (l, a) -> (l, ex a)) args, s)
  | Ast.Ascribe (a, t, s) -> Ast.Ascribe (ex a, t, s)
  | Ast.Member (a, m, s) -> Ast.Member (ex a, m, s)
  | Ast.Method_call (r, m, args, s) -> Ast.Method_call (ex r, m, List.map (fun (l, a) -> (l, ex a)) args, s)
  | Ast.Force_unwrap (a, s) -> Ast.Force_unwrap (ex a, s)
  | Ast.Coalesce (a, b, s) -> Ast.Coalesce (ex a, ex b, s)
  | Ast.Ternary (c, a, b, s) -> Ast.Ternary (ex c, ex a, ex b, s)
  | Ast.Cast (a, t, c, s) -> Ast.Cast (ex a, t, c, s)
  | Ast.Closure (ps, r, b, s) -> Ast.Closure (ps, r, ex b, s)
  | Ast.Try (k, a, s) -> Ast.Try (k, ex a, s)
  | Ast.Await (a, s) -> Ast.Await (ex a, s)
  | Ast.Array_lit (es, s) -> Ast.Array_lit (List.map ex es, s)
  | Ast.Subscript (a, i, s) -> Ast.Subscript (ex a, ex i, s)

let rec exs (s : Ast.stmt) : Ast.stmt =
  let b stmts = List.map exs stmts in
  (* a macro in statement position (`#assert(...)` as its own statement) gets the statement-level
     expansion; otherwise recurse, expanding the contained expressions. (Statement variants are
     INLINE records, so we destructure & rebuild each.) *)
  match s with
  | Ast.Expr_stmt (Ast.MacroExpr (name, args, mspan), _) -> (
      match expand_macro_stmt name (List.map ex args) mspan with
      | Some s' -> s'
      | None -> Ast.Expr_stmt (ex (Ast.MacroExpr (name, args, mspan)), mspan))
  | Ast.Let { name; is_var; annot; value; span } -> Ast.Let { name; is_var; annot; value = ex value; span }
  | Ast.Assign { name; value; span } -> Ast.Assign { name; value = ex value; span }
  | Ast.Set_member { obj; field; value; span } -> Ast.Set_member { obj; field; value = ex value; span }
  | Ast.Set_subscript { arr; index; value; span } -> Ast.Set_subscript { arr; index = ex index; value = ex value; span }
  | Ast.Expr_stmt (e, s2) -> Ast.Expr_stmt (ex e, s2)
  | Ast.If { cond; then_blk; else_blk; span } -> Ast.If { cond = ex cond; then_blk = b then_blk; else_blk = Option.map b else_blk; span }
  | Ast.If_let { name; opt; then_blk; else_blk; span } -> Ast.If_let { name; opt = ex opt; then_blk = b then_blk; else_blk = Option.map b else_blk; span }
  | Ast.While { cond; body; span } -> Ast.While { cond = ex cond; body = b body; span }
  | Ast.For { var; lo; hi; body; span } -> Ast.For { var; lo = ex lo; hi = ex hi; body = b body; span }
  | Ast.For_in { var; seq; body; span } -> Ast.For_in { var; seq = ex seq; body = b body; span }
  | Ast.Switch { subject; cases; default; span } ->
      Ast.Switch { subject = ex subject; cases = List.map (fun (p, body) -> (p, b body)) cases; default = Option.map b default; span }
  | Ast.Return (eo, s2) -> Ast.Return (Option.map ex eo, s2)
  | Ast.Throw (e, s2) -> Ast.Throw (ex e, s2)
  | Ast.Do { body; catches; span } -> Ast.Do { body = b body; catches = List.map (fun (c : Ast.catch_clause) -> { c with Ast.cbody = b c.Ast.cbody }) catches; span }
  | Ast.Defer (body, s2) -> Ast.Defer (b body, s2)
  | Ast.Spawn (body, s2) -> Ast.Spawn (b body, s2)
  | (Ast.Break _ | Ast.Continue _) as s -> s

let expand_func (f : Ast.func_decl) : Ast.func_decl = { f with Ast.body = List.map exs f.Ast.body }

let expand_program (prog : Ast.program) : Ast.program =
  let item = function
    | Ast.IStmt s -> Ast.IStmt (exs s) (* top-level statements *)
    | Ast.IFunc f -> Ast.IFunc (expand_func f)
    | Ast.IClass c ->
        Ast.IClass
          { c with
            Ast.cinit = Option.map expand_func c.Ast.cinit;
            cmethods = List.map (fun (ov, m) -> (ov, expand_func m)) c.Ast.cmethods;
            cdeinit = Option.map (List.map exs) c.Ast.cdeinit }
    | other -> other
  in
  { prog with Ast.items = List.map item prog.Ast.items }
