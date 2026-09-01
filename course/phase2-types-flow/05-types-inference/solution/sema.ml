(* FROZEN SOLUTION — concept 05 sema: the bidirectional type checker.

   Two modes, mutually recursive:
     infer e        -> ty        synthesize a type (no expectation)
     check_expr e t -> unit      check e against an expected type t (pushes t down)

   The one coercion is Swift's `ExpressibleByIntegerLiteral`: an *integer literal*
   (recursively, an arithmetic expression of integer literals) may take type Double when a
   Double is expected — so `let d: Double = 1 + 2` works, but `let d: Double = i` (i: Int)
   does not. Full literal flexibility is a constraint-solver job (Phase 5); we special-case
   the common shapes.

   Everything is top-level and takes an explicit [ctx], so every piece can be unit-tested on
   its own: the two pure helpers directly, the judgments against a context you build. *)

type ctx = {
  env : (string, Types.ty * bool) Hashtbl.t;  (* name -> its type, and whether it is a `var` *)
  diags : Diagnostics.sink;
}

let create (diags : Diagnostics.sink) : ctx = { env = Hashtbl.create 16; diags }
let err (cx : ctx) span msg = Diagnostics.error cx.diags span msg

(* a "pure integer-literal" expression can flex to Double *)
let rec is_int_literal = function
    | Ast.Int_lit _ -> true
    | Ast.Unary (Ast.Neg, e, _) -> is_int_literal e
    | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div | Ast.Mod), a, b, _) ->
      is_int_literal a && is_int_literal b
  | _ -> false

(* unify two operands' types, letting an integer literal become Double *)
let unify l tl r tr : Types.ty option =
  if Types.equal tl tr then Some tl
  else if is_int_literal l && tr = Types.TDouble then Some Types.TDouble
  else if is_int_literal r && tl = Types.TDouble then Some Types.TDouble
  else None

let rec infer (cx : ctx) (e : Ast.expr) : Types.ty =
    match e with
    | Ast.Int_lit _ -> Types.TInt
    | Ast.Double_lit _ -> Types.TDouble
    | Ast.Bool_lit _ -> Types.TBool
    | Ast.String_lit _ -> Types.TString
    | Ast.Var (x, span) -> (
        match Hashtbl.find_opt cx.env x with
        | Some (t, _) -> t
        | None ->
            err cx span (Printf.sprintf "cannot find '%s' in scope" x);
            Types.TInt)
    | Ast.Unary (Ast.Neg, e0, span) ->
        let t = infer cx e0 in
        if Types.is_numeric t then t
        else (
          err cx span
            (Printf.sprintf "unary operator '-' cannot be applied to an operand of type '%s'"
               (Types.string_of_ty t));
          t)
    | Ast.Binary (op, l, r, span) -> infer_binary cx op l r span
    | Ast.Call (f, args, span) -> infer_call cx f args span
  and infer_binary cx op l r span : Types.ty =
    let tl = infer cx l and tr = infer cx r in
    let bad () =
      (* swiftc has two wordings, and picks by whether the operands agree:
           1 + true   -> cannot be applied to operands of type 'Int' and 'Bool'
           true < false -> cannot be applied to two 'Bool' operands *)
      err cx span
        (if tl = tr then
           Printf.sprintf "binary operator '%s' cannot be applied to two '%s' operands"
             (Ast.string_of_binop op) (Types.string_of_ty tl)
         else
           Printf.sprintf "binary operator '%s' cannot be applied to operands of type '%s' and '%s'"
             (Ast.string_of_binop op) (Types.string_of_ty tl) (Types.string_of_ty tr));
      Types.TInt
    in
    match op with
    | Ast.Add -> (
        match unify l tl r tr with
        | Some ((Types.TInt | Types.TDouble) as t) -> t
        | Some Types.TString -> Types.TString
        | _ -> bad ())
    | Ast.Sub | Ast.Mul | Ast.Div -> (
        match unify l tl r tr with Some ((Types.TInt | Types.TDouble) as t) -> t | _ -> bad ())
    | Ast.Mod -> ( match unify l tl r tr with Some Types.TInt -> Types.TInt | _ -> bad ())
    | Ast.Eq | Ast.Ne -> (
        match unify l tl r tr with
        | Some _ -> Types.TBool
        | None ->
            ignore (bad ());
            Types.TBool)
    | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge -> (
        match unify l tl r tr with
        | Some (Types.TInt | Types.TDouble | Types.TString) -> Types.TBool
        | _ ->
            ignore (bad ());
            Types.TBool)
  and infer_call cx f args span : Types.ty =
    if f = "print" then (
      (match args with
      | [ a ] -> ignore (infer cx a)
      | _ ->
          err cx span "print(_:) expects exactly one argument";
          List.iter (fun a -> ignore (infer cx a)) args);
      Types.TInt (* print returns Void; placeholder, unused as a value *))
    else (
      err cx span (Printf.sprintf "cannot find '%s' in scope" f);
      List.iter (fun a -> ignore (infer cx a)) args;
      Types.TInt)
  (* The checking direction. It calls [infer] as its fallback, and [infer] never calls back — so
   this is NOT part of the knot above. In a fuller language, where a construct's own type depends
   on an expectation pushed into a subterm, the two judgments do become mutually recursive. *)
let rec check_expr (cx : ctx) (e : Ast.expr) (expected : Types.ty) : unit =
  match e with
  | Ast.Int_lit _ ->
      (* integer literal: ExpressibleBy both Int and Double *)
      if expected = Types.TInt || expected = Types.TDouble then ()
      else
        err cx (Ast.expr_span e)
          (Printf.sprintf "cannot convert value of type 'Int' to specified type '%s'"
             (Types.string_of_ty expected))
  | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div), l, r, _) when Types.is_numeric expected ->
      (* push the expected numeric type into both operands: 1 + 2 checks as Double *)
      check_expr cx l expected;
      check_expr cx r expected
  | Ast.Binary (Ast.Mod, l, r, _) when expected = Types.TInt ->
      check_expr cx l Types.TInt;
      check_expr cx r Types.TInt
  | Ast.Unary (Ast.Neg, e0, _) when Types.is_numeric expected -> check_expr cx e0 expected
  | _ ->
      let t = infer cx e in
      if not (Types.equal t expected) then
        err cx (Ast.expr_span e)
          (Printf.sprintf "cannot convert value of type '%s' to specified type '%s'"
             (Types.string_of_ty t) (Types.string_of_ty expected))

let check_stmt (cx : ctx) (s : Ast.stmt) : unit =
    match s with
    | Ast.Let { name; is_var; annot; value; span } ->
        let t =
          match annot with
          | None -> infer cx value
          | Some tyname -> (
              match Types.of_name tyname with
              | Some t ->
                  check_expr cx value t;
                  t
              | None ->
                  err cx span (Printf.sprintf "cannot find type '%s' in scope" tyname);
                  infer cx value)
        in
        Hashtbl.replace cx.env name (t, is_var)
    | Ast.Assign { name; value; span } -> (
        match Hashtbl.find_opt cx.env name with
        | None ->
            err cx span (Printf.sprintf "cannot find '%s' in scope" name);
            ignore (infer cx value)
        | Some (t, is_var) ->
            if not is_var then
              err cx span (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant" name);
            check_expr cx value t)
    | Ast.Expr_stmt (e, _) -> ignore (infer cx e)

let check (prog : Ast.program) (diags : Diagnostics.sink) : unit =
  let cx = create diags in
  List.iter (check_stmt cx) prog.Ast.stmts
