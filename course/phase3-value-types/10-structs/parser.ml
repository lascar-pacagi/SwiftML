(* FROZEN SOLUTION — concept 07 parser (carries 05–06; adds functions + return). Phase-1 recursive-descent + Pratt, plus the new
   prefixes (Double/Bool/String literals) and type annotations. The comparison operators
   are wired through the (given) infix_bp / binop_of_kind tables. *)

type t = { toks : Token.t array; mutable pos : int; diags : Diagnostics.sink }

let create (tokens : Token.t list) (diags : Diagnostics.sink) : t =
  { toks = Array.of_list tokens; pos = 0; diags }

let peek (p : t) : Token.t = p.toks.(p.pos)
let peek_kind (p : t) : Token.kind = (peek p).Token.kind

let peek_kind_at (p : t) (n : int) : Token.kind =
  let i = p.pos + n in
  if i < Array.length p.toks then p.toks.(i).Token.kind else Token.Eof

let advance (p : t) : Token.t =
  let tok = p.toks.(p.pos) in
  if p.pos < Array.length p.toks - 1 then p.pos <- p.pos + 1;
  tok

let expect (p : t) (k : Token.kind) (what : string) : Token.t =
  let tok = peek p in
  if tok.Token.kind = k then advance p
  else (
    Diagnostics.error p.diags tok.Token.span (Printf.sprintf "expected %s" what);
    tok)

(* binding powers: arithmetic > comparison > && > || (Swift's precedence groups) *)
let infix_bp : Token.kind -> int option = function
  | Token.Star | Token.Slash | Token.Percent -> Some 20
  | Token.Plus | Token.Minus -> Some 10
  | Token.EqEq | Token.Ne | Token.Lt | Token.Le | Token.Gt | Token.Ge -> Some 5
  | Token.AmpAmp -> Some 4
  | Token.PipePipe -> Some 3
  | _ -> None

let binop_of_kind : Token.kind -> Ast.binop option = function
  | Token.Plus -> Some Ast.Add
  | Token.Minus -> Some Ast.Sub
  | Token.Star -> Some Ast.Mul
  | Token.Slash -> Some Ast.Div
  | Token.Percent -> Some Ast.Mod
  | Token.EqEq -> Some Ast.Eq
  | Token.Ne -> Some Ast.Ne
  | Token.Lt -> Some Ast.Lt
  | Token.Le -> Some Ast.Le
  | Token.Gt -> Some Ast.Gt
  | Token.Ge -> Some Ast.Ge
  | Token.AmpAmp -> Some Ast.And
  | Token.PipePipe -> Some Ast.Or
  | _ -> None

let unary_bp = 100
let span_between (lo : Token.span) (hi : Token.span) : Token.span = { Token.lo = lo.Token.lo; hi = hi.Token.hi }

(* `as` sits at Swift's CastingPrecedence: above the comparisons, below arithmetic. *)
let cast_bp = 7

(* Reading the type name after `as`; `parse_ident` is defined below the expression parser. *)
let parse_ident_ty (p : t) (what : string) : string * Token.span =
  match peek_kind p with
  | Token.Ident s -> let t = advance p in (s, t.Token.span)
  | _ ->
      let t = peek p in
      Diagnostics.error p.diags t.Token.span (Printf.sprintf "expected %s" what);
      ("_", t.Token.span)

let rec parse_expr_bp (p : t) (min_bp : int) : Ast.expr =
  let lhs =
    match peek_kind p with
    | Token.Int n -> let t = advance p in Ast.Int_lit (n, t.Token.span)
    | Token.Float f -> let t = advance p in Ast.Double_lit (f, t.Token.span)
    | Token.String s -> let t = advance p in Ast.String_lit (s, t.Token.span)
    | Token.Kw_true -> let t = advance p in Ast.Bool_lit (true, t.Token.span)
    | Token.Kw_false -> let t = advance p in Ast.Bool_lit (false, t.Token.span)
    | Token.Ident name ->
        let t = advance p in
        if peek_kind p = Token.LParen then (
          ignore (advance p);
          let args = parse_call_args p in
          let rp = expect p Token.RParen "')'" in
          Ast.Call (name, args, span_between t.Token.span rp.Token.span))
        else Ast.Var (name, t.Token.span)
    | Token.LParen ->
        ignore (advance p);
        let e = parse_expr_bp p 0 in
        ignore (expect p Token.RParen "')'");
        e
    | Token.Minus ->
        let t = advance p in
        let operand = parse_expr_bp p unary_bp in
        Ast.Unary (Ast.Neg, operand, span_between t.Token.span (Ast.expr_span operand))
    | _ ->
        let t = peek p in
        Diagnostics.error p.diags t.Token.span "expected expression";
        ignore (advance p);
        Ast.Int_lit (0, t.Token.span)
  in
  let lhs = parse_postfix p lhs in
  let rec loop lhs =
    (* `e as T` — not a binary operator (its right side is a type NAME) but it binds like one. *)
    if peek_kind p = Token.Kw_as && cast_bp >= min_bp then (
      ignore (advance p);
      let name, tspan = parse_ident_ty p "type after 'as'" in
      loop (Ast.Ascribe (lhs, name, span_between (Ast.expr_span lhs) tspan)))
    else
    match infix_bp (peek_kind p) with
    | Some bp when bp >= min_bp ->
        let op_tok = advance p in
        let op = match binop_of_kind op_tok.Token.kind with Some o -> o | None -> assert false in
        let rhs = parse_expr_bp p (bp + 1) in
        loop (Ast.Binary (op, lhs, rhs, span_between (Ast.expr_span lhs) (Ast.expr_span rhs)))
    | _ -> lhs
  in
  loop lhs

(* postfix `.field` member access (chained): binds tighter than any infix operator — concept 10 *)
and parse_postfix (p : t) (e : Ast.expr) : Ast.expr =
  if peek_kind p = Token.Dot then (
    ignore (advance p);
    match peek_kind p with
    | Token.Ident fld ->
        let ft = advance p in
        parse_postfix p (Ast.Member (e, fld, span_between (Ast.expr_span e) ft.Token.span))
    | _ ->
        Diagnostics.error p.diags (peek p).Token.span "expected a member name";
        e)
  else e

(* call/init arguments: each is `[label:] expr` (the label is an Ident followed by ':') *)
and parse_call_args (p : t) : Ast.arg list =
  if peek_kind p = Token.RParen then []
  else
    let rec loop acc =
      let label =
        match peek_kind p with
        | Token.Ident l when peek_kind_at p 1 = Token.Colon ->
            ignore (advance p (* label *));
            ignore (advance p (* ':' *));
            Some l
        | _ -> None
      in
      let e = parse_expr_bp p 0 in
      let arg = (label, e) in
      if peek_kind p = Token.Comma then (ignore (advance p); loop (arg :: acc)) else List.rev (arg :: acc)
    in
    loop []

let parse_expr (p : t) : Ast.expr = parse_expr_bp p 0

let parse_ident (p : t) (what : string) : string * Token.span =
  match peek_kind p with
  | Token.Ident s -> let t = advance p in (s, t.Token.span)
  | _ ->
      let t = peek p in
      Diagnostics.error p.diags t.Token.span (Printf.sprintf "expected %s" what);
      ("_", t.Token.span)

(* optional ": TypeName" annotation *)
let parse_annot (p : t) : string option =
  if peek_kind p = Token.Colon then (
    ignore (advance p);
    let name, _ = parse_ident p "a type name" in
    Some name)
  else None

(* a brace-delimited block: "{" { statement NEWLINE } [ statement ] "}" — a newline SEPARATES
   statements, blank lines are skipped, and the closing "}" ends the last statement. *)
let rec parse_block (p : t) : Ast.stmt list =
  ignore (expect p Token.LBrace "'{'");
  let rec loop acc =
    while peek_kind p = Token.Newline do ignore (advance p) done;
    match peek_kind p with
    | Token.RBrace ->
        ignore (advance p);
        List.rev acc
    | Token.Eof ->
        ignore (expect p Token.RBrace "'}'");
        List.rev acc
    | _ ->
        let s = parse_stmt p in
        (* `block ::= "{" { statement NEWLINE } [ statement ] "}"`: a newline SEPARATES statements
           here exactly as it does at top level, and the closing `}` ends the last one — so
           `if c { x = 1 }` stays legal but `if c { x = 1 y = 2 }` is an error, as in Swift. *)
        (match peek_kind p with
        | Token.Newline -> ignore (advance p)
        | Token.RBrace | Token.Eof -> ()
        | _ -> Diagnostics.error p.diags (peek p).Token.span "expected newline or end of statement");
        loop (s :: acc)
  in
  loop []

and parse_if (p : t) : Ast.stmt =
  let kw = advance p (* if *) in
  let cond = parse_expr p in
  let then_blk = parse_block p in
  let else_blk =
    if peek_kind p = Token.Kw_else then (
      ignore (advance p);
      if peek_kind p = Token.Kw_if then Some [ parse_if p ] (* else if *)
      else Some (parse_block p))
    else None
  in
  Ast.If { cond; then_blk; else_blk; span = kw.Token.span }

and parse_stmt (p : t) : Ast.stmt =
  match peek_kind p with
  | Token.Kw_if -> parse_if p
  | Token.Kw_while ->
      let kw = advance p in
      let cond = parse_expr p in
      let body = parse_block p in
      Ast.While { cond; body; span = kw.Token.span }
  | Token.Kw_for ->
      let kw = advance p in
      let var, _ = parse_ident p "a loop variable" in
      ignore (expect p Token.Kw_in "'in'");
      let lo = parse_expr p in
      ignore (expect p Token.DotDotLt "'..<'");
      let hi = parse_expr p in
      let body = parse_block p in
      Ast.For { var; lo; hi; body; span = kw.Token.span }
  | Token.Kw_break -> let t = advance p in Ast.Break t.Token.span
  | Token.Kw_continue -> let t = advance p in Ast.Continue t.Token.span
  | Token.Kw_return ->
      let kw = advance p in
      (match peek_kind p with
      | Token.Newline | Token.RBrace | Token.Eof -> Ast.Return (None, kw.Token.span)
      | _ -> Ast.Return (Some (parse_expr p), kw.Token.span))
  | Token.Kw_let | Token.Kw_var ->
      let kw = advance p in
      let is_var = kw.Token.kind = Token.Kw_var in
      let name, _ = parse_ident p "identifier" in
      let annot = parse_annot p in
      ignore (expect p Token.Eq "'='");
      let value = parse_expr p in
      Ast.Let { name; is_var; annot; value; span = span_between kw.Token.span (Ast.expr_span value) }
  | Token.Ident name when peek_kind_at p 1 = Token.Eq ->
      let id = advance p in
      ignore (advance p);
      let value = parse_expr p in
      Ast.Assign { name; value; span = span_between id.Token.span (Ast.expr_span value) }
  (* `p.x = e` — a member assignment (concept 10); v0 handles one level (var.field) *)
  | Token.Ident obj when peek_kind_at p 1 = Token.Dot && peek_kind_at p 3 = Token.Eq ->
      let id = advance p (* obj *) in
      ignore (advance p (* . *));
      let field, _ = parse_ident p "a member name" in
      ignore (advance p (* = *));
      let value = parse_expr p in
      Ast.Set_member { obj; field; value; span = span_between id.Token.span (Ast.expr_span value) }
  | _ ->
      let e = parse_expr p in
      Ast.Expr_stmt (e, Ast.expr_span e)

(* `( [label] name: Type , … )` — comma-separated parameters. The optional external label
   (Swift's `_ a: Int` for positional calls, or `ext a: Int`) is parsed and discarded; we
   call positionally and don't check labels (a simplification — see the explainer). *)
let parse_params (p : t) : Ast.param list =
  ignore (expect p Token.LParen "'('");
  if peek_kind p = Token.RParen then (ignore (advance p); [])
  else
    let rec loop acc =
      let first, _ = parse_ident p "a parameter name" in
      (* `name :` -> label = name; `label name :` -> skip the external label, keep [name] *)
      let pname = if peek_kind p = Token.Colon then first else fst (parse_ident p "a parameter name") in
      ignore (expect p Token.Colon "':'");
      let ptype, _ = parse_ident p "a parameter type" in
      let acc = { Ast.pname; ptype } :: acc in
      if peek_kind p = Token.Comma then (ignore (advance p); loop acc)
      else (ignore (expect p Token.RParen "')'"); List.rev acc)
    in
    loop []

(* `func name ( params ) [ -> Type ] { body }` *)
let parse_func (p : t) : Ast.func_decl =
  let kw = advance p (* func *) in
  let fname, _ = parse_ident p "a function name" in
  let params = parse_params p in
  let ret =
    if peek_kind p = Token.Arrow then (
      ignore (advance p);
      let t, _ = parse_ident p "a return type" in
      Some t)
    else None
  in
  let body = parse_block p in
  { Ast.fname; params; ret; body; fspan = kw.Token.span }

(* `struct Name { (var|let) name: Type … }` — stored properties in order (concept 10) *)
let parse_struct (p : t) : Ast.struct_decl =
  let kw = advance p (* struct *) in
  let sname, _ = parse_ident p "a struct name" in
  ignore (expect p Token.LBrace "'{'");
  let rec loop acc =
    while peek_kind p = Token.Newline do ignore (advance p) done;
    match peek_kind p with
    | Token.RBrace -> ignore (advance p); List.rev acc
    | Token.Eof -> ignore (expect p Token.RBrace "'}'"); List.rev acc
    | Token.Kw_let | Token.Kw_var ->
        let fld_var = (advance p).Token.kind = Token.Kw_var in
        let fld_name, _ = parse_ident p "a property name" in
        ignore (expect p Token.Colon "':'");
        let fld_ty, _ = parse_ident p "a property type" in
        (match peek_kind p with Token.Newline -> ignore (advance p) | _ -> ());
        loop ({ Ast.fld_name; fld_ty; fld_var } :: acc)
    | _ ->
        let t = peek p in
        Diagnostics.error p.diags t.Token.span "expected a stored property: 'var name: Type'";
        ignore (advance p);
        loop acc
  in
  let sfields = loop [] in
  { Ast.sname; sfields; sspan = kw.Token.span }

(* A program is a sequence of top-level items: function declarations and statements. *)
let parse_program (p : t) : Ast.program =
  let skip_newlines () = while peek_kind p = Token.Newline do ignore (advance p) done in
  let rec loop acc =
    skip_newlines ();
    match peek_kind p with
    | Token.Eof -> { Ast.items = List.rev acc }
    | Token.Kw_func ->
        let f = parse_func p in
        (match peek_kind p with
        | Token.Newline -> ignore (advance p)
        | Token.Eof -> ()
        | _ -> Diagnostics.error p.diags (peek p).Token.span "expected newline or end of statement");
        loop (Ast.IFunc f :: acc)
    | Token.Kw_struct ->
        let s = parse_struct p in
        (match peek_kind p with Token.Newline -> ignore (advance p) | _ -> ());
        loop (Ast.IStruct s :: acc)
    | _ ->
        let s = parse_stmt p in
        (match peek_kind p with
        | Token.Newline -> ignore (advance p)
        | Token.Eof -> ()
        | _ -> Diagnostics.error p.diags (peek p).Token.span "expected newline or end of statement");
        loop (Ast.IStmt s :: acc)
  in
  loop []
