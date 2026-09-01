(* The parser: turn a token stream into an [Ast.program].

   Hand-written recursive descent (statements) + Pratt / precedence climbing
   (expressions), mirroring:
     swift/lib/Parse/Parser.cpp      (the cursor + expect/consume helpers)
     swift/lib/Parse/ParseStmt.cpp   (statement dispatch)
     swift/lib/Parse/ParseExpr.cpp   (parseExprSequence — Swift's precedence folding)

   >>> You build this in concept  phase1-minimal/02-parser. <<<
   The cursor helpers, the binding-power table and the two small span/identifier
   helpers are given; you write the three functions marked TODO(02...). See the
   explainer §3 for a step-by-step walk-through, §2 for why Pratt parsing works. *)

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

let peek_at (p : t) (n : int) : Token.t option =
  let i = p.pos + n in
  if i < Array.length p.toks then Some p.toks.(i) else None

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
let power_bp = 200
let span_between (lo : Token.span) (hi : Token.span) : Token.span =
  { Token.lo = lo.Token.lo; hi = hi.Token.hi }

(* --- expressions: Pratt parser --------------------------------------------- *)

let rec parse_expr_bp (p : t) (min_bp : int) : Ast.expr =
  (* TODO(02a): parse one expression, absorbing only operators whose binding power is
     >= [min_bp]. A prefix (literal / variable / call / '(' expr ')' / unary minus), then
     the infix fold. Report a missing expression rather than raising, and keep parsing.
     Walk-through: explainer §3.1-2. *)
  let rec loop left =
    let token = peek p in
    let token' = peek_at p 1 in
    if token.kind = Star && 
        Option.exists (fun t -> t.Token.kind = Star) token' &&
        Option.exists (fun t -> token.span.hi = t.Token.span.lo) token' &&
        power_bp >= min_bp then begin
      ignore (advance p);
      ignore (advance p);
      let right = parse_expr_bp p power_bp in 
      Ast.Call ("pow", [left; right],
                span_between (Ast.expr_span left) (Ast.expr_span right))
      |> loop
    end else begin
      match infix_bp token.kind with  
      | Some op_bp when op_bp >= min_bp -> begin
        ignore (advance p);
        let right = parse_expr_bp p (op_bp + 1) in 
        Ast.Binary (Option.get (binop_of_kind token.kind),
                    left, right,
                    span_between (Ast.expr_span left) (Ast.expr_span right))
        |> loop
      end
      | _ -> left
    end
  in
  loop (parse_prefix p)
  (* ignore (p, min_bp, parse_call_args);
  failwith "TODO(02a): implement Parser.parse_expr_bp (the Pratt loop)" *)

and parse_prefix (p : t) : Ast.expr =
    let token = advance p in
    match token.kind with
    | Int i -> Ast.Int_lit (i, token.span)
    | Ident id -> begin
      if peek_kind p = LParen then begin
        ignore (advance p);
        let args = parse_call_args p in
        let token' = expect p RParen "expected right parenthesis" in
        Call (id, args, span_between token.span token'.span)
      end else Ast.Var (id, token.span)
    end
    | LParen -> begin
      let expr = parse_expr_bp p 0 in
      ignore (expect p RParen "expected right parenthesis");
      expr
    end
    | Minus -> begin
      let expr = parse_expr_bp p unary_bp in
      Ast.Unary (Ast.Neg, expr, span_between token.span (Ast.expr_span expr))
    end
    | kind -> begin
      Diagnostics.error p.diags token.span 
        (Printf.sprintf "expected expression given %s" (Token.string_of_kind kind));
      while peek_kind p <> Eof && peek_kind p <> Newline do 
        ignore (advance p)
      done;
      Ast.Int_lit (42, token.span) 
    end

(* Zero-or-more comma-separated arguments, up to the closing ')'. *)
and parse_call_args (p : t) : Ast.expr list =
  (* TODO(02a): zero or more expressions separated by ',', in source order. *)
  if peek_kind p = RParen then []
  else 
    let arg = parse_expr_bp p 0 in
    if peek_kind p <> Comma then [arg]
    else begin
      ignore (advance p);
      arg :: parse_call_args p
    end
  (* ignore p;
  failwith "TODO(02a): implement Parser.parse_call_args" *)

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
  (* TODO(02b): one statement — a `let`/`var` binding, a reassignment, or a bare
     expression. Explainer §3.3 (note which case needs a token of lookahead). *)
  match peek_kind p with 
  | Kw_let -> begin
    let token = advance p in
    let (id, _) = parse_ident p "let ident" in
    ignore (expect p Eq "expected ident");
    let expr = parse_expr_bp p 0 in 
    Ast.Let { name = id; is_var = false; value = expr; 
              span = span_between token.span (Ast.expr_span expr) }
  end
  | Kw_var -> begin
    let token = advance p in
    let (id, _) = parse_ident p "var ident" in
    ignore (expect p Eq "expected ident");
    let expr = parse_expr_bp p 0 in 
    Ast.Let { name = id; is_var = true; value = expr; 
              span = span_between token.span (Ast.expr_span expr) }
  end
  | Ident id when peek_kind_at p 1 = Eq -> begin 
    let token = advance p in
    ignore (advance p);
    let expr = parse_expr_bp p 0 in
    Ast.Assign { name = id; value = expr; 
                  span = span_between token.span (Ast.expr_span expr) }    
  end
  | _ -> begin
    let expr = parse_expr_bp p 0 in
    Ast.Expr_stmt (expr, Ast.expr_span expr)
  end
  (* ignore p;
  failwith "TODO(02b): implement Parser.parse_stmt" *)

(* Whole file: skip blank lines, parse statements until Eof, consuming the Newline
   (or Eof) that terminates each. *)
let parse_program (p : t) : Ast.program =
  (* TODO(02c): every statement in the file, in source order, each terminated by a
     newline (or Eof). Blank lines are not statements. Explainer §3.4. *)
  let rec loop stmts =
    match peek_kind p with
    | Eof -> ignore (advance p); stmts
    | Newline -> ignore (advance p); loop stmts 
    | _ -> 
      let stmts = parse_stmt p :: stmts in
      (match peek_kind p with 
      | Eof -> ()
      | _ -> ignore (expect p Newline "expected newline"));
      loop stmts
  in
  { stmts = loop [] |> List.rev }
  (* ignore p;
  failwith "TODO(02c): implement Parser.parse_program" *)
