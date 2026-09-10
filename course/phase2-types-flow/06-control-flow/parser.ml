(* Parser — concept 06 (skeleton). Concepts 01–05 are filled in. You write the TODO(06) holes:
   the two new operators' rows in infix_bp / binop_of_kind, then parse_block, parse_if, and the
   control-flow cases of parse_stmt. Reference: solution/parser.ml. *)

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

let expect (parser : t) (k : Token.kind) (description : string) : Token.t =
  let token = peek parser in
  if token.Token.kind = k then advance parser
  else (
    Diagnostics.error parser.diagnostics token.Token.span (Printf.sprintf "expected %s" description);
    token)

(* Binding powers: higher binds tighter, and the Pratt loop keeps folding while the next
   operator's power is at least the one it was called with. Concepts 05's rows are here.
   TODO(06): give `&&` and `||` theirs. Both are LOOSER than a comparison, and they differ
   from each other — §2's precedence table has the numbers and Swift's group names. *)
let infix_bp : Token.kind -> int option = function
  | Token.Star | Token.Slash | Token.Percent -> Some 20
  | Token.Plus | Token.Minus -> Some 10
  | Token.EqEq | Token.Ne | Token.Lt | Token.Le | Token.Gt | Token.Ge -> Some 5
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
  (* TODO(06): the two new tokens map to `Ast.And` and `Ast.Or`. *)
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

(* a brace-delimited block: { (Newline | stmt Newline)* } *)
let rec parse_block (parser : t) : Ast.stmt list =
  ignore parser;
  ignore parse_if;
  (* TODO(06): a `{ ... }` block — the statements inside, blank lines skipped. §3. *)
  failwith "TODO(06): parse a { ... } block"

and parse_if (parser : t) : Ast.stmt =
  ignore parser;
  (* TODO(06): `if cond { } else { }`, where `else if` nests as an If inside the else. §3. *)
  failwith "TODO(06): parse an if/else statement"

and parse_stmt (parser : t) : Ast.stmt =
  match peek_kind parser with
  (* TODO(06): the control-flow statements — if / while / for-in-a-range / break / continue.
     The let-var, assignment and expression cases below are given. §3. *)
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
