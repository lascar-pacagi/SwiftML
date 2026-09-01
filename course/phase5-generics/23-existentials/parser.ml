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
    | Token.Kw_nil -> let t = advance p in Ast.Nil t.Token.span
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
  (* `??` (nil-coalescing): binds a bit tighter than comparison, right-associative — concept 13 *)
  let coalesce_bp = 6 in
  let ternary_bp = 2 in
  let rec loop lhs =
    (* `e as T` — not a binary operator (its right side is a type NAME) but it binds like one.
       `as?`/`as!` are DYNAMIC casts and stay in parse_postfix. *)
    if peek_kind p = Token.Kw_as && cast_bp >= min_bp
       && peek_kind_at p 1 <> Token.Question && peek_kind_at p 1 <> Token.Bang then (
      ignore (advance p);
      let name, tspan = parse_ident_ty p "a type name" in
      loop (Ast.Ascribe (lhs, name, span_between (Ast.expr_span lhs) tspan)))
    else
    if peek_kind p = Token.Question && peek_kind_at p 1 = Token.Question && coalesce_bp >= min_bp then (
      ignore (advance p);
      ignore (advance p);
      let rhs = parse_expr_bp p coalesce_bp in
      loop (Ast.Coalesce (lhs, rhs, span_between (Ast.expr_span lhs) (Ast.expr_span rhs))))
    else if peek_kind p = Token.Question && peek_kind_at p 1 <> Token.Question && ternary_bp >= min_bp then (
      ignore (advance p);
      let then_e = parse_expr_bp p 0 in
      ignore (expect p Token.Colon "':'");
      let else_e = parse_expr_bp p ternary_bp in
      loop (Ast.Ternary (lhs, then_e, else_e, span_between (Ast.expr_span lhs) (Ast.expr_span else_e))))
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

(* postfix `.name`/`.name(args)` (member/method), `!` (force unwrap), and `as?`/`as!`
   (dynamic casts — concept 23), chained *)
and parse_postfix (p : t) (e : Ast.expr) : Ast.expr =
  if peek_kind p = Token.Bang then (
    let t = advance p in
    parse_postfix p (Ast.Force_unwrap (e, span_between (Ast.expr_span e) t.Token.span)))
  else if peek_kind p = Token.Kw_as
          && (peek_kind_at p 1 = Token.Question || peek_kind_at p 1 = Token.Bang) then (
    ignore (advance p);
    let conditional =
      match peek_kind p with
      | Token.Question -> ignore (advance p); true
      | Token.Bang -> ignore (advance p); false
      | _ ->
          Diagnostics.error p.diags (peek p).Token.span "expected '?' or '!' after 'as' (only as?/as! in this subset)";
          true
    in
    let tn, ts =
      match peek_kind p with
      | Token.Ident n -> let t = advance p in (n, t.Token.span)
      | _ ->
          Diagnostics.error p.diags (peek p).Token.span "expected a type name";
          ("Int", (peek p).Token.span)
    in
    parse_postfix p (Ast.Cast (e, tn, conditional, span_between (Ast.expr_span e) ts)))
  else if peek_kind p = Token.Dot then (
    ignore (advance p);
    match peek_kind p with
    | Token.Ident name ->
        let nt = advance p in
        if peek_kind p = Token.LParen then (
          ignore (advance p);
          let args = parse_call_args p in
          let rp = expect p Token.RParen "')'" in
          parse_postfix p (Ast.Method_call (e, name, args, span_between (Ast.expr_span e) rp.Token.span)))
        else parse_postfix p (Ast.Member (e, name, span_between (Ast.expr_span e) nt.Token.span))
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

(* a type reference: a name optionally followed by `?` for an optional (`Int?`). We carry the
   `?` in the string and let sema resolve it to `TOptional` — concept 13. Concept 21: an
   `any` prefix (Swift's explicit existential spelling, `any P`) is accepted and normalized
   away — `P` and `any P` denote the same type here, exactly as in swiftc. *)
let parse_type_name (p : t) (what : string) : string =
  let name, _ = parse_ident p what in
  let name = if name = "any" then fst (parse_ident p what) else name in
  if peek_kind p = Token.Question then (ignore (advance p); name ^ "?") else name

(* optional ": TypeName" annotation *)
let parse_annot (p : t) : string option =
  if peek_kind p = Token.Colon then (ignore (advance p); Some (parse_type_name p "a type name")) else None

(* `( (let name | _) , … )` — the bindings of an enum-case pattern (concept 12) *)
let parse_bindings (p : t) : Ast.pat_binding list =
  ignore (advance p (* '(' *));
  if peek_kind p = Token.RParen then (ignore (advance p); [])
  else
    let rec loop acc =
      let b =
        match peek_kind p with
        | Token.Kw_let -> ignore (advance p); Ast.Bind (fst (parse_ident p "a binding name"))
        | Token.Ident "_" -> ignore (advance p); Ast.Ignore
        | Token.Ident _ -> Ast.Bind (fst (parse_ident p "a binding name")) (* lenient: bare name *)
        | _ -> Diagnostics.error p.diags (peek p).Token.span "expected 'let name' or '_'"; Ast.Ignore
      in
      if peek_kind p = Token.Comma then (ignore (advance p); loop (b :: acc))
      else (ignore (expect p Token.RParen "')'"); List.rev (b :: acc))
    in
    loop []

(* a `case` pattern: `.name`, `.name(bindings)`, or an Int literal (concept 12) *)
let parse_pattern (p : t) : Ast.pattern =
  match peek_kind p with
  | Token.Dot ->
      ignore (advance p);
      let name, _ = parse_ident p "an enum case name" in
      let bindings = if peek_kind p = Token.LParen then parse_bindings p else [] in
      Ast.PEnumCase (name, bindings)
  | Token.Int n -> ignore (advance p); Ast.PInt n
  | Token.Minus -> (
      ignore (advance p);
      match peek_kind p with
      | Token.Int n -> ignore (advance p); Ast.PInt (-n)
      | _ -> Diagnostics.error p.diags (peek p).Token.span "expected a pattern"; Ast.PInt 0)
  | _ -> Diagnostics.error p.diags (peek p).Token.span "expected a 'case' pattern"; Ast.PInt 0

(* a brace-delimited block: { (Newline | stmt Newline)* } *)
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
        (match peek_kind p with Token.Newline -> ignore (advance p) | _ -> ());
        loop (s :: acc)
  in
  loop []

and parse_if (p : t) : Ast.stmt =
  let kw = advance p (* if *) in
  (* `if let name = opt { … } [else { … }]` — optional binding (concept 13) *)
  if peek_kind p = Token.Kw_let then (
    ignore (advance p (* let *));
    let name, _ = parse_ident p "a binding name" in
    ignore (expect p Token.Eq "'='");
    let opt = parse_expr p in
    let then_blk = parse_block p in
    let else_blk =
      if peek_kind p = Token.Kw_else then (
        ignore (advance p);
        if peek_kind p = Token.Kw_if then Some [ parse_if p ] else Some (parse_block p))
      else None
    in
    Ast.If_let { name; opt; then_blk; else_blk; span = kw.Token.span })
  else
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

(* `switch subject { case <pat>: <stmts> … [default: <stmts>] }` — concept 12. A case body runs
   until the next `case`/`default`/`}` (Swift cases don't fall through). *)
and parse_switch (p : t) : Ast.stmt =
  let kw = advance p (* switch *) in
  let subject = parse_expr p in
  ignore (expect p Token.LBrace "'{'");
  let skipnl () = while peek_kind p = Token.Newline do ignore (advance p) done in
  let parse_case_body () =
    let rec loop acc =
      skipnl ();
      match peek_kind p with
      | Token.Kw_case | Token.Kw_default | Token.RBrace | Token.Eof -> List.rev acc
      | _ ->
          let s = parse_stmt p in
          (match peek_kind p with Token.Newline -> ignore (advance p) | _ -> ());
          loop (s :: acc)
    in
    loop []
  in
  let rec arms cs default =
    skipnl ();
    match peek_kind p with
    | Token.RBrace -> ignore (advance p); (List.rev cs, default)
    | Token.Eof -> ignore (expect p Token.RBrace "'}'"); (List.rev cs, default)
    | Token.Kw_case ->
        ignore (advance p);
        let pat = parse_pattern p in
        ignore (expect p Token.Colon "':'");
        arms ((pat, parse_case_body ()) :: cs) default
    | Token.Kw_default ->
        ignore (advance p);
        ignore (expect p Token.Colon "':'");
        arms cs (Some (parse_case_body ()))
    | _ ->
        Diagnostics.error p.diags (peek p).Token.span "expected 'case' or 'default'";
        ignore (advance p);
        arms cs default
  in
  let cases, default = arms [] None in
  Ast.Switch { subject; cases; default; span = kw.Token.span }

and parse_stmt (p : t) : Ast.stmt =
  match peek_kind p with
  | Token.Kw_if -> parse_if p
  | Token.Kw_switch -> parse_switch p
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
      let ptype = parse_type_name p "a parameter type" in
      let acc = { Ast.pname; ptype } :: acc in
      if peek_kind p = Token.Comma then (ignore (advance p); loop acc)
      else (ignore (expect p Token.RParen "')'"); List.rev acc)
    in
    loop []

(* `func name [<T: P, …>] ( params ) [ -> Type ] [where T: P] { body }` — the generics
   clause and the where-clause both attach constraints to type parameters (concept 22) *)
let parse_func (p : t) : Ast.func_decl =
  let kw = advance p (* func *) in
  let fname, _ = parse_ident p "a function name" in
  let generics =
    if peek_kind p <> Token.Lt then []
    else (
      ignore (advance p);
      let rec loop acc =
        let n, _ = parse_ident p "a type parameter" in
        let c = if peek_kind p = Token.Colon then (ignore (advance p); Some (fst (parse_ident p "a constraint"))) else None in
        if peek_kind p = Token.Comma then (ignore (advance p); loop ((n, c) :: acc))
        else (ignore (expect p Token.Gt "'>'"); List.rev ((n, c) :: acc))
      in
      loop [])
  in
  let params = parse_params p in
  let ret =
    if peek_kind p = Token.Arrow then (
      ignore (advance p);
      let t = parse_type_name p "a return type" in
      Some t)
    else None
  in
  (* `where T: P` — merge into the generics list *)
  let generics = ref generics in
  if peek_kind p = Token.Kw_where then begin
    ignore (advance p);
    let rec wloop () =
      let n, sp = parse_ident p "a type parameter" in
      ignore (expect p Token.Colon "':'");
      let c, _ = parse_ident p "a constraint" in
      (if List.mem_assoc n !generics then
         generics := List.map (fun (g, oc) -> if g = n then (g, Some c) else (g, oc)) !generics
       else Diagnostics.error p.diags sp (Printf.sprintf "cannot find type '%s' in scope" n));
      if peek_kind p = Token.Comma then (ignore (advance p); wloop ())
    in
    wloop ()
  end;
  let body = parse_block p in
  { Ast.fname; generics = !generics; params; ret; body; fspan = kw.Token.span }

(* `struct Name [: P, Q] { (var|let) name: Type … func … }` — stored properties + methods
   (concept 10; conformances and methods are concept 21). *)
let parse_struct (p : t) : Ast.struct_decl =
  let kw = advance p (* struct *) in
  let sname, _ = parse_ident p "a struct name" in
  let sconforms =
    if peek_kind p <> Token.Colon then []
    else (
      ignore (advance p);
      let rec confs acc =
        let n, _ = parse_ident p "a protocol name" in
        if peek_kind p = Token.Comma then (ignore (advance p); confs (n :: acc)) else List.rev (n :: acc)
      in
      confs [])
  in
  ignore (expect p Token.LBrace "'{'");
  let rec loop flds meths =
    while peek_kind p = Token.Newline do ignore (advance p) done;
    match peek_kind p with
    | Token.RBrace -> ignore (advance p); (List.rev flds, List.rev meths)
    | Token.Eof -> ignore (expect p Token.RBrace "'}'"); (List.rev flds, List.rev meths)
    | Token.Kw_let | Token.Kw_var ->
        ignore (advance p (* let/var *));
        let fld_name, _ = parse_ident p "a property name" in
        ignore (expect p Token.Colon "':'");
        let fld_ty = parse_type_name p "a property type" in
        (match peek_kind p with Token.Newline -> ignore (advance p) | _ -> ());
        loop ({ Ast.fld_name; fld_ty } :: flds) meths
    | Token.Kw_func ->
        let m = parse_func p in
        (match peek_kind p with Token.Newline -> ignore (advance p) | _ -> ());
        loop flds (m :: meths)
    | _ ->
        let t = peek p in
        Diagnostics.error p.diags t.Token.span "expected a stored property or a method";
        ignore (advance p);
        loop flds meths
  in
  let sfields, smethods = loop [] [] in
  { Ast.sname; sconforms; sfields; smethods; sspan = kw.Token.span }

(* `protocol Name { func name(params) [-> T] … }` — method requirements: signatures with NO
   body (concept 21). The requirement order is the witness-table slot order. *)
let parse_proto (p : t) : Ast.proto_decl =
  let kw = advance p (* protocol *) in
  let pname, _ = parse_ident p "a protocol name" in
  ignore (expect p Token.LBrace "'{'");
  let rec loop acc =
    while peek_kind p = Token.Newline do ignore (advance p) done;
    match peek_kind p with
    | Token.RBrace -> ignore (advance p); List.rev acc
    | Token.Eof -> ignore (expect p Token.RBrace "'}'"); List.rev acc
    | Token.Kw_func ->
        ignore (advance p (* func *));
        let rname, _ = parse_ident p "a requirement name" in
        let rparams = parse_params p in
        let rret =
          if peek_kind p = Token.Arrow then (ignore (advance p); Some (parse_type_name p "a return type"))
          else None
        in
        (match peek_kind p with Token.Newline -> ignore (advance p) | _ -> ());
        loop ({ Ast.rname; rparams; rret } :: acc)
    | _ ->
        let t = peek p in
        Diagnostics.error p.diags t.Token.span "expected a method requirement: 'func name(...) -> T'";
        ignore (advance p);
        loop acc
  in
  let reqs = loop [] in
  { Ast.pname; reqs; pspan = kw.Token.span }

(* `enum Name [: Raw] { case a; case b(T, U) … }` — cases in order, optional payloads. We
   ignore explicit `= raw` (implicit raws = index); see the explainer. (concept 11) *)
let parse_enum (p : t) : Ast.enum_decl =
  let kw = advance p (* enum *) in
  let ename, _ = parse_ident p "an enum name" in
  let eraw = if peek_kind p = Token.Colon then (ignore (advance p); Some (fst (parse_ident p "a raw type"))) else None in
  ignore (expect p Token.LBrace "'{'");
  let parse_payload () =
    if peek_kind p <> Token.LParen then []
    else (
      ignore (advance p);
      let rec loop acc =
        let t = parse_type_name p "an associated-value type" in
        if peek_kind p = Token.Comma then (ignore (advance p); loop (t :: acc))
        else (ignore (expect p Token.RParen "')'"); List.rev (t :: acc))
      in
      loop [])
  in
  let rec loop acc =
    while peek_kind p = Token.Newline do ignore (advance p) done;
    match peek_kind p with
    | Token.RBrace -> ignore (advance p); List.rev acc
    | Token.Eof -> ignore (expect p Token.RBrace "'}'"); List.rev acc
    | Token.Kw_case ->
        ignore (advance p (* case *));
        (* one `case` line may list several comma-separated names: `case red, green, blue` *)
        let rec cases acc =
          let cname, _ = parse_ident p "a case name" in
          let payload = parse_payload () in
          let c = { Ast.cname; payload } in
          if peek_kind p = Token.Comma then (ignore (advance p); cases (c :: acc)) else List.rev (c :: acc)
        in
        let cs = cases [] in
        (match peek_kind p with Token.Newline -> ignore (advance p) | _ -> ());
        (* prepend the line's cases so the outer `List.rev acc` restores declaration order *)
        loop (List.rev_append cs acc)
    | _ ->
        let t = peek p in
        Diagnostics.error p.diags t.Token.span "expected a 'case' declaration";
        ignore (advance p);
        loop acc
  in
  let ecases = loop [] in
  { Ast.ename; ecases; eraw; espan = kw.Token.span }

(* A program is a sequence of top-level items: function declarations and statements. *)
let parse_program (p : t) : Ast.program =
  let skip_newlines () = while peek_kind p = Token.Newline do ignore (advance p) done in
  let rec loop acc =
    skip_newlines ();
    match peek_kind p with
    | Token.Eof -> { Ast.items = List.rev acc }
    | Token.Kw_func ->
        let f = parse_func p in
        (match peek_kind p with Token.Newline -> ignore (advance p) | _ -> ());
        loop (Ast.IFunc f :: acc)
    | Token.Kw_struct ->
        let s = parse_struct p in
        (match peek_kind p with Token.Newline -> ignore (advance p) | _ -> ());
        loop (Ast.IStruct s :: acc)
    | Token.Kw_enum ->
        let e = parse_enum p in
        (match peek_kind p with Token.Newline -> ignore (advance p) | _ -> ());
        loop (Ast.IEnum e :: acc)
    | Token.Kw_protocol ->
        let pr = parse_proto p in
        (match peek_kind p with Token.Newline -> ignore (advance p) | _ -> ());
        loop (Ast.IProto pr :: acc)
    | _ ->
        let s = parse_stmt p in
        (match peek_kind p with
        | Token.Newline -> ignore (advance p)
        | Token.Eof -> ()
        | _ -> Diagnostics.error p.diags (peek p).Token.span "expected newline or end of statement");
        loop (Ast.IStmt s :: acc)
  in
  loop []
