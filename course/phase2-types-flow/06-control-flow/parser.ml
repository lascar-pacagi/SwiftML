(* Parser — concept 06 (skeleton). Concepts 1–05 are filled in; the && / || precedence is
   wired through infix_bp / binop_of_kind. You write the TODO(06) holes: parse_block,
   parse_if, and the control-flow cases of parse_stmt. Reference: solution/parser.ml. *)

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
  let rec loop lhs =
    match infix_bp (peek_kind p) with
    | Some bp when bp >= min_bp ->
        let op_tok = advance p in
        let op = match binop_of_kind op_tok.Token.kind with Some o -> o | None -> assert false in
        let rhs = parse_expr_bp p (bp + 1) in
        loop (Ast.Binary (op, lhs, rhs, span_between (Ast.expr_span lhs) (Ast.expr_span rhs)))
    | _ -> lhs
  in
  loop lhs

and parse_call_args (p : t) : Ast.expr list =
  if peek_kind p = Token.RParen then []
  else
    let rec loop acc =
      let e = parse_expr_bp p 0 in
      if peek_kind p = Token.Comma then (ignore (advance p); loop (e :: acc)) else List.rev (e :: acc)
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

(* a brace-delimited block: { (Newline | stmt Newline)* } *)
let rec parse_block (p : t) : Ast.stmt list =
  ignore p;
  ignore parse_if;
  (* TODO(06): a `{ ... }` block — the statements inside, blank lines skipped. §3. *)
  failwith "TODO(06): parse a { ... } block"

and parse_if (p : t) : Ast.stmt =
  ignore p;
  (* TODO(06): `if cond { } else { }`, where `else if` nests as an If inside the else. §3. *)
  failwith "TODO(06): parse an if/else statement"

and parse_stmt (p : t) : Ast.stmt =
  match peek_kind p with
  (* TODO(06): the control-flow statements — if / while / for-in-a-range / break / continue.
     The let-var, assignment and expression cases below are given. §3. *)
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
  | _ ->
      let e = parse_expr p in
      Ast.Expr_stmt (e, Ast.expr_span e)

let parse_program (p : t) : Ast.program =
  let rec skip_newlines () =
    if peek_kind p = Token.Newline then (ignore (advance p); skip_newlines ())
  in
  let rec loop acc =
    skip_newlines ();
    match peek_kind p with
    | Token.Eof -> { Ast.stmts = List.rev acc }
    | _ ->
        let s = parse_stmt p in
        (match peek_kind p with
        | Token.Newline -> ignore (advance p)
        | Token.Eof -> ()
        | _ -> Diagnostics.error p.diags (peek p).Token.span "expected newline or end of statement");
        loop (s :: acc)
  in
  loop []
