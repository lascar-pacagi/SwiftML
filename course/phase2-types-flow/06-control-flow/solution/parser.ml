(* FROZEN SOLUTION — concept 06 parser. Phase-1 recursive-descent + Pratt, plus the new
   prefixes (Double/Bool/String literals) and type annotations. The comparison operators
   are wired through the (given) infix_bp / binop_of_kind tables. *)

type t = { tokens : Token.t array; mutable pos : int; diagnostics : Diagnostics.sink }

let create (tokens : Token.t list) (diagnostics : Diagnostics.sink) : t =
  { tokens = Array.of_list tokens; pos = 0; diagnostics }

let peek (parser : t) : Token.t = parser.tokens.(parser.pos)
let peek_kind (parser : t) : Token.kind = (peek parser).Token.kind

let peek_kind_at (parser : t) (n : int) : Token.kind =
  let i = parser.pos + n in
  if i < Array.length parser.tokens then parser.tokens.(i).Token.kind else Token.Eof

let advance (parser : t) : Token.t =
  let token = parser.tokens.(parser.pos) in
  if parser.pos < Array.length parser.tokens - 1 then parser.pos <- parser.pos + 1;
  token

(* GIVEN — a lookahead that may have to un-read description it read. `mark` remembers where the cursor
   is; `put_back` returns it there. Use them when you must peek PAST something to decide, and
   leave the input untouched if the answer is no: `else` may start a line of its own, so
   `parse_if` skips newlines to look for it and puts the cursor back when it finds anything
   else — those newlines are the separator the caller is about to need. *)
let mark (parser : t) : int = parser.pos
let put_back (parser : t) (saved : int) : unit = parser.pos <- saved

let expect (parser : t) (k : Token.kind) (description : string) : Token.t =
  let token = peek parser in
  if token.Token.kind = k then advance parser
  else (
    Diagnostics.error parser.diagnostics token.Token.span (Printf.sprintf "expected %s" description);
    token)

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
let parse_ident_ty (parser : t) (description : string) : string * Token.span =
  match peek_kind parser with
  | Token.Ident s -> let t = advance parser in (s, t.Token.span)
  | _ ->
      let t = peek parser in
      Diagnostics.error parser.diagnostics t.Token.span (Printf.sprintf "expected %s" description);
      ("_", t.Token.span)

let rec parse_expr_bp (parser : t) (minimum_binding_power : int) : Ast.expr =
  let left =
    match peek_kind parser with
    | Token.Int n -> let t = advance parser in Ast.Int_lit (n, t.Token.span)
    | Token.Float f -> let t = advance parser in Ast.Double_lit (f, t.Token.span)
    | Token.String s -> let t = advance parser in Ast.String_lit (s, t.Token.span)
    | Token.Kw_true -> let t = advance parser in Ast.Bool_lit (true, t.Token.span)
    | Token.Kw_false -> let t = advance parser in Ast.Bool_lit (false, t.Token.span)
    | Token.Ident name ->
        let t = advance parser in
        if peek_kind parser = Token.LParen then (
          ignore (advance parser);
          let args = parse_call_args parser in
          let rp = expect parser Token.RParen "')'" in
          Ast.Call (name, args, span_between t.Token.span rp.Token.span))
        else Ast.Var (name, t.Token.span)
    | Token.LParen ->
        ignore (advance parser);
        let expression = parse_expr_bp parser 0 in
        ignore (expect parser Token.RParen "')'");
        expression
    | Token.Minus ->
        let t = advance parser in
        let operand = parse_expr_bp parser unary_bp in
        Ast.Unary (Ast.Neg, operand, span_between t.Token.span (Ast.expr_span operand))
    | _ ->
        let t = peek parser in
        Diagnostics.error parser.diagnostics t.Token.span "expected expression";
        ignore (advance parser);
        Ast.Int_lit (0, t.Token.span)
  in
  let rec loop left =
    (* `expression as T` — not a binary operator (its right side is a type NAME) but it binds like one. *)
    if peek_kind parser = Token.Kw_as && cast_bp >= minimum_binding_power then (
      ignore (advance parser);
      let name, tspan = parse_ident_ty parser "type after 'as'" in
      loop (Ast.Ascribe (left, name, span_between (Ast.expr_span left) tspan)))
    else
    match infix_bp (peek_kind parser) with
    | Some bp when bp >= minimum_binding_power ->
        let op_tok = advance parser in
        let op = match binop_of_kind op_tok.Token.kind with Some o -> o | None -> assert false in
        let right = parse_expr_bp parser (bp + 1) in
        loop (Ast.Binary (op, left, right, span_between (Ast.expr_span left) (Ast.expr_span right)))
    | _ -> left
  in
  loop left

and parse_call_args (parser : t) : Ast.expr list =
  if peek_kind parser = Token.RParen then []
  else
    let rec loop accumulator =
      let expression = parse_expr_bp parser 0 in
      if peek_kind parser = Token.Comma then (ignore (advance parser); loop (expression :: accumulator)) else List.rev (expression :: accumulator)
    in
    loop []

let parse_expr (parser : t) : Ast.expr = parse_expr_bp parser 0

let parse_ident (parser : t) (description : string) : string * Token.span =
  match peek_kind parser with
  | Token.Ident s -> let t = advance parser in (s, t.Token.span)
  | _ ->
      let t = peek parser in
      Diagnostics.error parser.diagnostics t.Token.span (Printf.sprintf "expected %s" description);
      ("_", t.Token.span)

(* optional ": TypeName" annotation *)
let parse_annot (parser : t) : string option =
  if peek_kind parser = Token.Colon then (
    ignore (advance parser);
    let name, _ = parse_ident parser "a type name" in
    Some name)
  else None

(* a brace-delimited block, with `nl` one or more Newlines:
     block ::= "{" [ nl ] [ statement { nl statement } ] [ nl ] "}"
   so blank lines are free, a newline SEPARATES statements, and the closing "}" ends the
   last one — `{ x = 1 }` is legal, `{ x = 1 y = 2 }` is not. *)
let rec parse_block (parser : t) : Ast.stmt list =
  ignore (expect parser Token.LBrace "'{'");
  let rec loop accumulator =
    while peek_kind parser = Token.Newline do ignore (advance parser) done;
    match peek_kind parser with
    | Token.RBrace ->
        ignore (advance parser);
        List.rev accumulator
    | Token.Eof ->
        ignore (expect parser Token.RBrace "'}'");
        List.rev accumulator
    | _ ->
        let s = parse_stmt parser in
        (* `nl` is one or more Newlines, so a run of blank lines is one separator; the separator
           sits BETWEEN statements and the closing `}` ends the last one — `if c { x = 1 }` is
           legal, `if c { x = 1 y = 2 }` is an error, as in Swift. *)
        (match peek_kind parser with
        | Token.Newline -> ignore (advance parser)
        | Token.RBrace | Token.Eof -> ()
        | _ -> Diagnostics.error parser.diagnostics (peek parser).Token.span "expected newline or end of statement");
        loop (s :: accumulator)
  in
  loop []

and parse_if (parser : t) : Ast.stmt =
  let keyword = advance parser (* if *) in
  let cond = parse_expr parser in
  let then_blk = parse_block parser in
  (* `else` may start the next LINE — swiftc accepts that, so look past newlines for it, and put
     them back when description follows is not an `else` (they are the separator the caller needs). *)
  let saved = parser.pos in
  while peek_kind parser = Token.Newline do ignore (advance parser) done;
  if peek_kind parser <> Token.Kw_else then parser.pos <- saved;
  (* `else` may start a later line — look past the newlines for it, and put the cursor back if
     description follows is not an `else`. *)
  let saved = mark parser in
  while peek_kind parser = Token.Newline do ignore (advance parser) done;
  if peek_kind parser <> Token.Kw_else then put_back parser saved;
  let else_blk =
    if peek_kind parser = Token.Kw_else then (
      ignore (advance parser);
      if peek_kind parser = Token.Kw_if then Some [ parse_if parser ] (* else if *)
      else Some (parse_block parser))
    else None
  in
  Ast.If { cond; then_blk; else_blk; span = keyword.Token.span }

and parse_stmt (parser : t) : Ast.stmt =
  match peek_kind parser with
  | Token.Kw_if -> parse_if parser
  | Token.Kw_while ->
      let keyword = advance parser in
      let cond = parse_expr parser in
      let body = parse_block parser in
      Ast.While { cond; body; span = keyword.Token.span }
  | Token.Kw_for ->
      let keyword = advance parser in
      let var, _ = parse_ident parser "a loop variable" in
      ignore (expect parser Token.Kw_in "'in'");
      let lo = parse_expr parser in
      ignore (expect parser Token.DotDotLt "'..<'");
      let hi = parse_expr parser in
      let body = parse_block parser in
      Ast.For { var; lo; hi; body; span = keyword.Token.span }
  | Token.Kw_break -> let t = advance parser in Ast.Break t.Token.span
  | Token.Kw_continue -> let t = advance parser in Ast.Continue t.Token.span
  | Token.Kw_let | Token.Kw_var ->
      let keyword = advance parser in
      let is_var = keyword.Token.kind = Token.Kw_var in
      let name, _ = parse_ident parser "identifier" in
      let annot = parse_annot parser in
      ignore (expect parser Token.Eq "'='");
      let value = parse_expr parser in
      Ast.Let { name; is_var; annot; value; span = span_between keyword.Token.span (Ast.expr_span value) }
  | Token.Ident name when peek_kind_at parser 1 = Token.Eq ->
      let id = advance parser in
      ignore (advance parser);
      let value = parse_expr parser in
      Ast.Assign { name; value; span = span_between id.Token.span (Ast.expr_span value) }
  | _ ->
      let expression = parse_expr parser in
      Ast.Expr_stmt (expression, Ast.expr_span expression)

let parse_program (parser : t) : Ast.program =
  let rec skip_newlines () =
    if peek_kind parser = Token.Newline then (ignore (advance parser); skip_newlines ())
  in
  let rec loop accumulator =
    skip_newlines ();
    match peek_kind parser with
    | Token.Eof -> { Ast.stmts = List.rev accumulator }
    | _ ->
        let s = parse_stmt parser in
        (match peek_kind parser with
        | Token.Newline -> ignore (advance parser)
        | Token.Eof -> ()
        | _ -> Diagnostics.error parser.diagnostics (peek parser).Token.span "expected newline or end of statement");
        loop (s :: accumulator)
  in
  loop []
