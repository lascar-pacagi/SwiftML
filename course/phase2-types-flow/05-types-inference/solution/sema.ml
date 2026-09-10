(* FROZEN SOLUTION — concept 05 sema: the bidirectional type checker.

   Two modes, mutually recursive:
     infer expression        -> ty        synthesize a type (no expectation)
     check_expr expression t -> unit
       check expression against an expected type t (pushes t down)

   The one coercion is Swift's `ExpressibleByIntegerLiteral`: an *integer literal*
   (recursively, an arithmetic expression of integer literals) may take type Double when a
   Double is expected — so `let d: Double = 1 + 2` works, but `let d: Double = i` (i: Int)
   does not. Full literal flexibility is a constraint-solver job (Phase 5); we special-case
   the common shapes.

   Everything is top-level and takes an explicit [context], so every piece can be unit-tested on
   its own: the two pure helpers directly, the judgments against a context you build. *)

type context = {
  environment : (string, Types.ty * bool) Hashtbl.t;
      (* name -> its type, and whether it is a `var` *)
  diagnostics : Diagnostics.sink;
}

let create (diagnostics : Diagnostics.sink) : context =
  { environment = Hashtbl.create 16; diagnostics }

let report_error (context : context) span msg =
  Diagnostics.error context.diagnostics span msg

(* a "pure integer-literal" expression can flex to Double *)
let rec is_int_literal = function
  | Ast.Int_lit _ -> true
  | Ast.Unary (Ast.Neg, expression, _) -> is_int_literal expression
  | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div | Ast.Mod), a, b, _) ->
      is_int_literal a && is_int_literal b
  | _ -> false

(* unify two operands' types, letting an integer literal become Double *)
let unify l tl r tr : Types.ty option =
  if Types.equal tl tr then Some tl
  else if is_int_literal l && tr = Types.TDouble then Some Types.TDouble
  else if is_int_literal r && tl = Types.TDouble then Some Types.TDouble
  else None

let rec infer (context : context) (expression : Ast.expr) : Types.ty =
  match expression with
  | Ast.Int_lit _ -> Types.TInt
  | Ast.Double_lit _ -> Types.TDouble
  | Ast.Bool_lit _ -> Types.TBool
  | Ast.String_lit _ -> Types.TString
  | Ast.Var (x, span) -> (
      match Hashtbl.find_opt context.environment x with
      | Some (t, _) -> t
      | None ->
          report_error context span
            (Printf.sprintf "cannot find '%s' in scope" x);
          Types.TInt)
  | Ast.Unary (Ast.Neg, e0, span) ->
      let t = infer context e0 in
      if Types.is_numeric t then t
      else (
        report_error context span
          (Printf.sprintf
             "unary operator '-' cannot be applied to an operand of type '%s'"
             (Types.string_of_ty t));
        t)
  | Ast.Binary (op, l, r, span) -> infer_binary context op l r span
  | Ast.Call (f, args, span) -> infer_call context f args span
  (* The one place `infer` calls `check`: the type is written down, so there is nothing to
       synthesise — the operand is CHECKED against it, which is what lets `1 as Double` work
       and `i as Double` fail. *)
  | Ast.Ascribe (e0, tyname, span) -> (
      match Types.of_name tyname with
      | Some t ->
          check_expr context e0 t;
          t
      | None ->
          report_error context span
            (Printf.sprintf "cannot find type '%s' in scope" tyname);
          infer context e0)

and infer_binary context op l r span : Types.ty =
  let tl = infer context l and tr = infer context r in
  let bad () =
    (* swiftc has two wordings, and picks by whether the operands agree:
           1 + true     -> cannot be applied to operands of type 'Int' and 'Bool'
           true < false -> cannot be applied to two 'Bool' operands *)
    report_error context span
      (if tl = tr then
         Printf.sprintf
           "binary operator '%s' cannot be applied to two '%s' operands"
           (Ast.string_of_binop op) (Types.string_of_ty tl)
       else
         Printf.sprintf
           "binary operator '%s' cannot be applied to operands of type '%s' \
            and '%s'"
           (Ast.string_of_binop op) (Types.string_of_ty tl)
           (Types.string_of_ty tr))
  in
  let is_ordered t = Types.is_numeric t || t = Types.TString in
  (* Match on the UNIFIED type, not on tl/tr: the coercion happens inside [unify], so a guard
       over the raw operand types cannot see it — `1 == 2.0` would look like Int vs Double and be
       rejected, and `i + 2.0` would look acceptable right up until [unify] returned None. *)
  match (unify l tl r tr, op) with
  | Some t, Ast.Add when Types.is_numeric t -> t
  | Some Types.TString, Ast.Add -> Types.TString (* `+` concatenates *)
  | Some t, (Ast.Sub | Ast.Mul | Ast.Div) when Types.is_numeric t -> t
  | Some Types.TInt, Ast.Mod -> Types.TInt (* no `%` on Double, as in Swift *)
  | Some _, (Ast.Eq | Ast.Ne) ->
      Types.TBool (* any single type may be compared *)
  | Some t, (Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge) when is_ordered t -> Types.TBool
  (* Everything else is an error. The recovery type differs: a failed comparison is still a
       Bool, or the enclosing `if` reports a second problem nobody wrote. *)
  | _, (Ast.Eq | Ast.Ne | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge) ->
      bad ();
      Types.TBool
  | _ ->
      bad ();
      Types.TInt

and infer_call context f args span : Types.ty =
  if f = "print" then (
    (match args with
    | [ a ] -> ignore (infer context a)
    | _ ->
        report_error context span "print(_:) expects exactly one argument";
        List.iter (fun a -> ignore (infer context a)) args);
    Types.TInt (* print returns Void; placeholder, unused as a value *))
  else (
    report_error context span (Printf.sprintf "cannot find '%s' in scope" f);
    List.iter (fun a -> ignore (infer context a)) args;
    Types.TInt)
(* The checking direction — and the other half of a genuine knot: [check_expr] falls back to
   [infer], and [infer] calls [check_expr] for `expression as T`. Neither can be defined without the
   other, which is what "the two judgments are mutually recursive" means in practice. *)

and check_expr (context : context) (expression : Ast.expr) (expected : Types.ty)
    : unit =
  match expression with
  | Ast.Int_lit _ ->
      (* integer literal: ExpressibleBy both Int and Double *)
      if expected = Types.TInt || expected = Types.TDouble then ()
      else
        report_error context (Ast.expr_span expression)
          (Printf.sprintf
             "cannot convert value of type 'Int' to specified type '%s'"
             (Types.string_of_ty expected))
  | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div), l, r, _)
    when Types.is_numeric expected ->
      (* push the expected numeric type into both operands: 1 + 2 checks as Double *)
      check_expr context l expected;
      check_expr context r expected
  | Ast.Binary (Ast.Mod, l, r, _) when expected = Types.TInt ->
      check_expr context l Types.TInt;
      check_expr context r Types.TInt
  | Ast.Unary (Ast.Neg, e0, _) when Types.is_numeric expected ->
      check_expr context e0 expected
  | _ ->
      let t = infer context expression in
      if not (Types.equal t expected) then
        report_error context (Ast.expr_span expression)
          (Printf.sprintf
             "cannot convert value of type '%s' to specified type '%s'"
             (Types.string_of_ty t)
             (Types.string_of_ty expected))

let check_stmt (context : context) (s : Ast.stmt) : unit =
  match s with
  | Ast.Let { name; is_var; annot; value; span } ->
      let t =
        match annot with
        | None -> infer context value
        | Some tyname -> (
            match Types.of_name tyname with
            | Some t ->
                check_expr context value t;
                t
            | None ->
                report_error context span
                  (Printf.sprintf "cannot find type '%s' in scope" tyname);
                infer context value)
      in
      Hashtbl.replace context.environment name (t, is_var)
  | Ast.Assign { name; value; span } -> (
      match Hashtbl.find_opt context.environment name with
      | None ->
          report_error context span
            (Printf.sprintf "cannot find '%s' in scope" name);
          ignore (infer context value)
      | Some (t, is_var) ->
          if not is_var then
            report_error context span
              (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant"
                 name);
          check_expr context value t)
  | Ast.Expr_stmt (expression, _) -> ignore (infer context expression)

let check (program : Ast.program) (diagnostics : Diagnostics.sink) : unit =
  let context = create diagnostics in
  List.iter (check_stmt context) program.Ast.stmts
