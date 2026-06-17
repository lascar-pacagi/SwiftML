(* FROZEN SOLUTION — concept 02-parser. Verified answer key for [parser.ml].
   Kept out of the build by `(dirs :standard \ solution)`. Drop-in copy of the stage
   module with the three TODO functions implemented. Verify by copying over
   ../parser.ml and running `dune build @phase1-minimal/02-parser/runtest`.

   Hand-written recursive descent (statements) + Pratt / precedence-climbing
   (expressions). Mirrors swift/lib/Parse/{Parser,ParseDecl,ParseStmt,ParseExpr}.cpp. *)

type t = {
  toks : Token.t array;
  mutable pos : int;
  diags : Diagnostics.sink;
}

let create (tokens : Token.t list) (diags : Diagnostics.sink) : t =
  { toks = Array.of_list tokens; pos = 0; diags }

(* --- cursor helpers --------------------------------------------------------- *)

let peek (p : t) : Token.t = p.toks.(p.pos)
let peek_kind (p : t) : Token.kind = (peek p).Token.kind

(* One-token lookahead, for distinguishing `c = …` (assignment) from `c + …`. *)
let peek_kind_at (p : t) (n : int) : Token.kind =
  let i = p.pos + n in
  if i < Array.length p.toks then p.toks.(i).Token.kind else Token.Eof

let advance (p : t) : Token.t =
  let tok = p.toks.(p.pos) in
  if p.pos < Array.length p.toks - 1 then p.pos <- p.pos + 1;
  tok

(* Consume a token of the expected kind, or report an error and return the current one. *)
let expect (p : t) (k : Token.kind) (what : string) : Token.t =
  let tok = peek p in
  if tok.Token.kind = k then advance p
  else (
    Diagnostics.error p.diags tok.Token.span (Printf.sprintf "expected %s" what);
    tok)

(* Pratt binding powers: higher binds tighter. (Phase 1 levels.) *)
let infix_bp : Token.kind -> int option = function
  | Token.Plus | Token.Minus -> Some 10
  | Token.Star | Token.Slash | Token.Percent -> Some 20
  | _ -> None

let binop_of_kind : Token.kind -> Ast.binop option = function
  | Token.Plus -> Some Ast.Add
  | Token.Minus -> Some Ast.Sub
  | Token.Star -> Some Ast.Mul
  | Token.Slash -> Some Ast.Div
  | Token.Percent -> Some Ast.Mod
  | _ -> None

(* Unary minus binds tighter than any binary operator. *)
let unary_bp = 100

let span_between (lo : Token.span) (hi : Token.span) : Token.span =
  { Token.lo = lo.Token.lo; hi = hi.Token.hi }

(* --- expressions: Pratt parser --------------------------------------------- *)

let rec parse_expr_bp (p : t) (min_bp : int) : Ast.expr =
  (* 1. prefix / "nud": literal, variable, call, parenthesised expr, or unary minus. *)
  let lhs =
    match peek_kind p with
    | Token.Int n ->
        let t = advance p in
        Ast.Int_lit (n, t.Token.span)
    | Token.Ident name ->
        let t = advance p in
        if peek_kind p = Token.LParen then (
          (* a call — in Phase 1 this is only print(_:) *)
          ignore (advance p (* '(' *));
          let args = parse_call_args p in
          let rp = expect p Token.RParen "')'" in
          Ast.Call (name, args, span_between t.Token.span rp.Token.span))
        else Ast.Var (name, t.Token.span)
    | Token.LParen ->
        ignore (advance p (* '(' *));
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
        Ast.Int_lit (0, t.Token.span) (* recovery placeholder *)
  in
  (* 2. infix / "led": fold operators that bind at least [min_bp]. Left-assoc via
     recursing on the right with [bp + 1]. *)
  let rec loop lhs =
    match infix_bp (peek_kind p) with
    | Some bp when bp >= min_bp ->
        let op_tok = advance p in
        let op =
          match binop_of_kind op_tok.Token.kind with Some o -> o | None -> assert false
        in
        let rhs = parse_expr_bp p (bp + 1) in
        loop (Ast.Binary (op, lhs, rhs, span_between (Ast.expr_span lhs) (Ast.expr_span rhs)))
    | _ -> lhs
  in
  loop lhs

(* Zero-or-more comma-separated arguments, up to the closing ')'. *)
and parse_call_args (p : t) : Ast.expr list =
  if peek_kind p = Token.RParen then []
  else
    let rec loop acc =
      let e = parse_expr_bp p 0 in
      if peek_kind p = Token.Comma then (
        ignore (advance p);
        loop (e :: acc))
      else List.rev (e :: acc)
    in
    loop []

let parse_expr (p : t) : Ast.expr = parse_expr_bp p 0

(* --- statements ------------------------------------------------------------- *)

(* Extract an identifier spelling, or report and recover with "_". *)
let parse_ident (p : t) (what : string) : string * Token.span =
  match peek_kind p with
  | Token.Ident s ->
      let t = advance p in
      (s, t.Token.span)
  | _ ->
      let t = peek p in
      Diagnostics.error p.diags t.Token.span (Printf.sprintf "expected %s" what);
      ("_", t.Token.span)

let parse_stmt (p : t) : Ast.stmt =
  match peek_kind p with
  | Token.Kw_let | Token.Kw_var ->
      let kw = advance p in
      let is_var = kw.Token.kind = Token.Kw_var in
      let name, _ = parse_ident p "identifier" in
      ignore (expect p Token.Eq "'='");
      let value = parse_expr p in
      Ast.Let { name; is_var; value; span = span_between kw.Token.span (Ast.expr_span value) }
  | Token.Ident name when peek_kind_at p 1 = Token.Eq ->
      (* reassignment: `c = expr` *)
      let id = advance p in
      ignore (advance p (* '=' *));
      let value = parse_expr p in
      Ast.Assign { name; value; span = span_between id.Token.span (Ast.expr_span value) }
  | _ ->
      let e = parse_expr p in
      Ast.Expr_stmt (e, Ast.expr_span e)

(* Whole file: skip blank lines, parse statements until Eof, consuming the Newline
   (or Eof) that terminates each. *)
let parse_program (p : t) : Ast.program =
  let rec skip_newlines () =
    if peek_kind p = Token.Newline then (
      ignore (advance p);
      skip_newlines ())
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
        | _ ->
            Diagnostics.error p.diags (peek p).Token.span
              "expected newline or end of statement");
        loop (s :: acc)
  in
  loop []
