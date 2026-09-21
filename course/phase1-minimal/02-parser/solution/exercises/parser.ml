(* FROZEN SOLUTION — concept 02-parser, WITH §6's EXERCISES APPLIED.
   Kept out of the build by `(dirs :standard \ solution)`. Run it with
   `make check-exercises C=phase1-minimal/02-parser`.

   This is `solution/parser.ml` plus exercise 1 (name the offending token, and recover to
   the next newline so one run reports one error per broken line) and exercise 2 (right-
   associative `**`, decided in the parser and desugared to a call). Read the stock answer
   key first: the differences are marked EX1 and EX2 below.

   Hand-written recursive descent (statements) + Pratt / precedence-climbing
   (expressions). Mirrors swift/lib/Parse/{Parser,ParseDecl,ParseStmt,ParseExpr}.cpp. *)

type t = {
  tokens : Token.t array;
  mutable pos : int;
  diagnostics : Diagnostics.sink;
}

let create (tokens : Token.t list) (diagnostics : Diagnostics.sink) : t =
  { tokens = Array.of_list tokens; pos = 0; diagnostics }

(* --- cursor helpers --------------------------------------------------------- *)

let peek (parser : t) : Token.t = parser.tokens.(parser.pos)
let peek_kind (parser : t) : Token.kind = (peek parser).Token.kind

(* One-token lookahead, for distinguishing `c = …` (assignment) from `c + …`. *)
let peek_kind_at (parser : t) (n : int) : Token.kind =
  let i = parser.pos + n in
  if i < Array.length parser.tokens then parser.tokens.(i).Token.kind
  else Token.Eof

let advance (parser : t) : Token.t =
  let token = parser.tokens.(parser.pos) in
  if parser.pos < Array.length parser.tokens - 1 then
    parser.pos <- parser.pos + 1;
  token

(* Report at the OFFENDING token — the one that was found, not the one that was hoped for.
   Every diagnostic in this file goes through here, so that rule lives in one place (the lexer
   has the same helper, for the same reason). The wording comes from explainer §2's table. *)
let report_error (parser : t) (message : string) : unit =
  Diagnostics.error parser.diagnostics (peek parser).Token.span message

(* Consume a token of the expected kind, or report an error and return the current one. *)
let expect (parser : t) (k : Token.kind) (description : string) : Token.t =
  let token = peek parser in
  if token.Token.kind = k then advance parser
  else (
    report_error parser (Printf.sprintf "expected %s" description);
    token)

(* Newlines separate declarations and statements in several grammar productions. *)
let skip_newlines (parser : t) : unit =
  while peek_kind parser = Token.Newline do
    ignore (advance parser)
  done

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

(* EX2. `**` outranks every binary operator in `infix_bp`, and below unary minus, so
   `-2 ** 2` is `-(2 ** 2)`. *)
let pow_bp = 30

(* EX2. The LEXER cannot decide whether `**` is one operator or two: C++ has the same
   problem with `>>` closing two templates versus shifting right, and settles it in the
   parser. Everything needed is already in the tokens — two stars are the exponent
   operator exactly when they TOUCH, and the spans say whether they do. That is also why
   `2 * * 3` stays an error. *)
let two_stars (parser : t) : bool =
  peek_kind parser = Token.Star
  && peek_kind_at parser 1 = Token.Star
  && parser.pos + 1 < Array.length parser.tokens
  && parser.tokens.(parser.pos).Token.span.Token.hi.Token.offset
     = parser.tokens.(parser.pos + 1).Token.span.Token.lo.Token.offset

let span_between (lo : Token.span) (hi : Token.span) : Token.span =
  { Token.lo = lo.Token.lo; hi = hi.Token.hi }

(* --- expressions: Pratt parser --------------------------------------------- *)

let rec parse_expr_bp (parser : t) (minimum_binding_power : int) : Ast.expr =
  (* 1. prefix / "nud": literal, variable, call, parenthesised expr, or unary minus. *)
  let left =
    match peek_kind parser with
    | Token.Int n ->
        let t = advance parser in
        Ast.Int_lit (n, t.Token.span)
    | Token.Ident name ->
        let t = advance parser in
        if peek_kind parser = Token.LParen then (
          (* a call — in Phase 1 this is only print(_:) *)
          ignore (advance parser (* '(' *));
          let args = parse_call_args parser in
          let rp = expect parser Token.RParen "')'" in
          Ast.Call (name, args, span_between t.Token.span rp.Token.span))
        else Ast.Var (name, t.Token.span)
    | Token.LParen ->
        ignore (advance parser (* '(' *));
        let expression = parse_expr_bp parser 0 in
        ignore (expect parser Token.RParen "')'");
        expression
    | Token.Minus ->
        let t = advance parser in
        let operand = parse_expr_bp parser unary_bp in
        Ast.Unary
          (Ast.Neg, operand, span_between t.Token.span (Ast.expr_span operand))
    | _ ->
        (* EX1: name the token that is actually there. "expected expression" leaves the
           reader hunting for which one; the message is the only thing they get. *)
        let t = peek parser in
        report_error parser
          (Printf.sprintf "expected an expression, found '%s'"
             (Token.string_of_kind t.Token.kind));
        ignore (advance parser);
        Ast.Int_lit (0, t.Token.span)
  in
  (* 2. infix / "led": fold operators that bind at least [minimum_binding_power]. Left-assoc via
     recursing on the right with [bp + 1]. *)
  let rec loop left =
    (* EX2: taken BEFORE infix_bp, which would otherwise see the first star as `*`. The
       recursion is at pow_bp, not pow_bp + 1 — that missing `+ 1` IS right-associativity,
       because it lets the right-hand side absorb another `**` at the same level. And the
       result is a CALL: `pow(a, b)` reuses a node that already exists, so neither the AST
       nor sema nor IRGen has to learn anything. *)
    if two_stars parser && pow_bp >= minimum_binding_power then (
      ignore (advance parser);
      ignore (advance parser);
      let right = parse_expr_bp parser pow_bp in
      loop
        (Ast.Call
           ( "pow",
             [ left; right ],
             span_between (Ast.expr_span left) (Ast.expr_span right) )))
    else
    match infix_bp (peek_kind parser) with
    | Some bp when bp >= minimum_binding_power ->
        let op_tok = advance parser in
        let op =
          match binop_of_kind op_tok.Token.kind with
          | Some o -> o
          | None -> assert false
        in
        let right = parse_expr_bp parser (bp + 1) in
        loop
          (Ast.Binary
             ( op,
               left,
               right,
               span_between (Ast.expr_span left) (Ast.expr_span right) ))
    | _ -> left
  in
  loop left

(* Zero-or-more comma-separated arguments, up to the closing ')'. *)
and parse_call_args (parser : t) : Ast.expr list =
  if peek_kind parser = Token.RParen then []
  else
    let rec loop accumulator =
      let expression = parse_expr_bp parser 0 in
      if peek_kind parser = Token.Comma then (
        ignore (advance parser);
        (* SE-0439: a comma MAY follow the last argument, so `f(1,)` is legal. A leading
           one is not — that is why this test is here and not at the top of the loop. *)
        if peek_kind parser = Token.RParen then List.rev (expression :: accumulator)
        else loop (expression :: accumulator))
      else List.rev (expression :: accumulator)
    in
    loop []

let parse_expr (parser : t) : Ast.expr = parse_expr_bp parser 0

(* --- statements ------------------------------------------------------------- *)

(* Extract an identifier spelling, or report and recover with "_". *)
let parse_ident (parser : t) (description : string) : string * Token.span =
  match peek_kind parser with
  | Token.Ident s ->
      let t = advance parser in
      (s, t.Token.span)
  | _ ->
      let t = peek parser in
      report_error parser (Printf.sprintf "expected %s" description);
      ("_", t.Token.span)

let parse_stmt (parser : t) : Ast.stmt =
  match peek_kind parser with
  | Token.Kw_let | Token.Kw_var ->
      let keyword = advance parser in
      let is_var = keyword.Token.kind = Token.Kw_var in
      let what = if is_var then "a variable name" else "a constant name" in
      let name, _ = parse_ident parser what in
      ignore (expect parser Token.Eq "'='");
      let value = parse_expr parser in
      Ast.Let
        {
          name;
          is_var;
          value;
          span = span_between keyword.Token.span (Ast.expr_span value);
        }
  | Token.Ident name when peek_kind_at parser 1 = Token.Eq ->
      (* reassignment: `c = expr` *)
      let id = advance parser in
      ignore (advance parser (* '=' *));
      let value = parse_expr parser in
      Ast.Assign
        { name; value; span = span_between id.Token.span (Ast.expr_span value) }
  | _ ->
      let expression = parse_expr parser in
      Ast.Expr_stmt (expression, Ast.expr_span expression)

(* Whole file: skip blank lines, parse statements until Eof, consuming the Newline
   (or Eof) that terminates each. *)
let parse_program (parser : t) : Ast.program =
  let rec loop accumulator =
    skip_newlines parser;
    match peek_kind parser with
    | Token.Eof -> { Ast.stmts = List.rev accumulator }
    | _ ->
        let s = parse_stmt parser in
        (match peek_kind parser with
        | Token.Newline -> ignore (advance parser)
        | Token.Eof -> ()
        | _ ->
            report_error parser
              "consecutive statements on a line must be separated by a newline";
            (* EX1: panic-mode recovery. Without it the parser stumbles token by token
               and one broken line becomes a cascade of six diagnostics; skipping to the
               next synchronizing token — here a newline, since that is what separates
               statements — reports the line once and still parses the ones after it. *)
            while
              match peek_kind parser with
              | Token.Newline | Token.Eof -> false
              | _ -> true
            do
              ignore (advance parser)
            done);
        loop (s :: accumulator)
  in
  loop []
