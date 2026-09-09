(* ANSWER KEY — concept 10 parser.  Carries the Phase-2 recursive-descent/Pratt parser and
   adds struct declarations, labeled initializer arguments, and member reads/writes. *)

type t = { tokens : Token.t array; mutable pos : int; diagnostics : Diagnostics.sink }

let create (tokens : Token.t list) (diagnostics : Diagnostics.sink) : t =
  { tokens = Array.of_list tokens; pos = 0; diagnostics }

let peek (parser : t) : Token.t = parser.tokens.(parser.pos)
let peek_kind (parser : t) : Token.kind = (peek parser).Token.kind

let peek_kind_at (parser : t) (lookahead : int) : Token.kind =
  let index = parser.pos + lookahead in
  if index < Array.length parser.tokens then parser.tokens.(index).Token.kind else Token.Eof

let advance (parser : t) : Token.t =
  let token = parser.tokens.(parser.pos) in
  if parser.pos < Array.length parser.tokens - 1 then parser.pos <- parser.pos + 1;
  token

(* GIVEN — a lookahead that may have to un-read what it read. `mark` remembers where the cursor
   is; `put_back` returns it there. Use them when you must peek PAST something to decide, and
   leave the input untouched if the answer is no: `else` may start a line of its own, so
   `parse_if` skips newlines to look for it and puts the cursor back when it finds anything
   else — those newlines are the separator the caller is about to need. *)
let mark (parser : t) : int = parser.pos
let put_back (parser : t) (saved_position : int) : unit = parser.pos <- saved_position

let expect (parser : t) (expected_kind : Token.kind) (description : string) : Token.t =
  let token = peek parser in
  if token.Token.kind = expected_kind then advance parser
  else (
    Diagnostics.error parser.diagnostics token.Token.span (Printf.sprintf "expected %s" description);
    token)

(* binding powers: arithmetic > comparison > && > || (Swift's precedence groups) *)
let infix_binding_power : Token.kind -> int option = function
  | Token.Star | Token.Slash | Token.Percent -> Some 20
  | Token.Plus | Token.Minus -> Some 10
  | Token.EqEq | Token.Ne | Token.Lt | Token.Le | Token.Gt | Token.Ge -> Some 5
  | Token.AmpAmp -> Some 4
  | Token.PipePipe -> Some 3
  | _ -> None

let binary_operator_of_kind : Token.kind -> Ast.binop option = function
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

let unary_binding_power = 100
let span_between (lo : Token.span) (hi : Token.span) : Token.span = { Token.lo = lo.Token.lo; hi = hi.Token.hi }

(* `as` sits at Swift's CastingPrecedence: above the comparisons, below arithmetic. *)
let cast_binding_power = 7

(* Reading the type name after `as`; `parse_ident` is defined below the expression parser. *)
let parse_type_name (parser : t) (description : string) : string * Token.span =
  match peek_kind parser with
  | Token.Ident name -> let token = advance parser in (name, token.Token.span)
  | _ ->
      let token = peek parser in
      Diagnostics.error parser.diagnostics token.Token.span (Printf.sprintf "expected %s" description);
      ("_", token.Token.span)

let rec parse_expr_bp (parser : t) (minimum_binding_power : int) : Ast.expr =
  let left =
    match peek_kind parser with
    | Token.Int integer -> let token = advance parser in Ast.Int_lit (integer, token.Token.span)
    | Token.Float number -> let token = advance parser in Ast.Double_lit (number, token.Token.span)
    | Token.String text -> let token = advance parser in Ast.String_lit (text, token.Token.span)
    | Token.Kw_true -> let token = advance parser in Ast.Bool_lit (true, token.Token.span)
    | Token.Kw_false -> let token = advance parser in Ast.Bool_lit (false, token.Token.span)
    | Token.Ident name ->
        let token = advance parser in
        if peek_kind parser = Token.LParen then (
          ignore (advance parser);
          let arguments = parse_call_args parser in
          let right_paren = expect parser Token.RParen "')'" in
          Ast.Call (name, arguments, span_between token.Token.span right_paren.Token.span))
        else Ast.Var (name, token.Token.span)
    | Token.LParen ->
        ignore (advance parser);
        let expression = parse_expr_bp parser 0 in
        ignore (expect parser Token.RParen "')'");
        expression
    | Token.Minus ->
        let token = advance parser in
        let operand = parse_expr_bp parser unary_binding_power in
        Ast.Unary (Ast.Neg, operand, span_between token.Token.span (Ast.expr_span operand))
    | _ ->
        let token = peek parser in
        Diagnostics.error parser.diagnostics token.Token.span "expected expression";
        ignore (advance parser);
        Ast.Int_lit (0, token.Token.span)
  in
  let left = parse_postfix parser left in
  let rec loop left =
    (* `expression as T` — not a binary operator (its right side is a type NAME) but it binds like one. *)
    if peek_kind parser = Token.Kw_as && cast_binding_power >= minimum_binding_power then (
      ignore (advance parser);
      let name, type_span = parse_type_name parser "type after 'as'" in
      loop (Ast.Ascribe (left, name, span_between (Ast.expr_span left) type_span)))
    else
    match infix_binding_power (peek_kind parser) with
    | Some binding_power when binding_power >= minimum_binding_power ->
        let operator_token = advance parser in
        let operator = match binary_operator_of_kind operator_token.Token.kind with Some operator -> operator | None -> assert false in
        let right = parse_expr_bp parser (binding_power + 1) in
        loop (Ast.Binary (operator, left, right, span_between (Ast.expr_span left) (Ast.expr_span right)))
    | _ -> left
  in
  loop left

(* postfix `.field` member access (chained): binds tighter than any infix operator — concept 10 *)
and parse_postfix (parser : t) (expression : Ast.expr) : Ast.expr =
  if peek_kind parser = Token.Dot then (
    ignore (advance parser);
    match peek_kind parser with
    | Token.Ident field_name ->
        let field_token = advance parser in
        parse_postfix parser
          (Ast.Member
             (expression, field_name,
              span_between (Ast.expr_span expression) field_token.Token.span))
    | _ ->
        Diagnostics.error parser.diagnostics (peek parser).Token.span "expected a member name";
        expression)
  else expression

(* call/init arguments: each is `[label:] expr` (the label is an Ident followed by ':') *)
and parse_call_args (parser : t) : Ast.arg list =
  if peek_kind parser = Token.RParen then []
  else
    let rec loop accumulator =
      let label =
        match peek_kind parser with
        | Token.Ident l when peek_kind_at parser 1 = Token.Colon ->
            ignore (advance parser (* label *));
            ignore (advance parser (* ':' *));
            Some l
        | _ -> None
      in
      let expression = parse_expr_bp parser 0 in
      let argument = (label, expression) in
      if peek_kind parser = Token.Comma then (ignore (advance parser); loop (argument :: accumulator)) else List.rev (argument :: accumulator)
    in
    loop []

let parse_expr (parser : t) : Ast.expr = parse_expr_bp parser 0

let parse_ident (parser : t) (description : string) : string * Token.span =
  match peek_kind parser with
  | Token.Ident name -> let token = advance parser in (name, token.Token.span)
  | _ ->
      let token = peek parser in
      Diagnostics.error parser.diagnostics token.Token.span (Printf.sprintf "expected %s" description);
      ("_", token.Token.span)

(* optional ": TypeName" annotation *)
let parse_type_annotation (parser : t) : string option =
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
        let statement = parse_statement parser in
        (* `nl` is one or more Newlines, so a run of blank lines is one separator; the separator
           sits BETWEEN statements and the closing `}` ends the last one — `if c { x = 1 }` is
           legal, `if c { x = 1 y = 2 }` is an error, as in Swift. *)
        (match peek_kind parser with
        | Token.Newline -> ignore (advance parser)
        | Token.RBrace | Token.Eof -> ()
        | _ -> Diagnostics.error parser.diagnostics (peek parser).Token.span "expected newline or end of statement");
        loop (statement :: accumulator)
  in
  loop []

and parse_if (parser : t) : Ast.stmt =
  let keyword = advance parser (* if *) in
  let condition = parse_expr parser in
  let then_block = parse_block parser in
  (* `else` may start a later line — look past the newlines for it, and put the cursor back if
     what follows is not an `else`. *)
  let saved_position = mark parser in
  while peek_kind parser = Token.Newline do ignore (advance parser) done;
  if peek_kind parser <> Token.Kw_else then put_back parser saved_position;
  let else_block =
    if peek_kind parser = Token.Kw_else then (
      ignore (advance parser);
      if peek_kind parser = Token.Kw_if then Some [ parse_if parser ] (* else if *)
      else Some (parse_block parser))
    else None
  in
  Ast.If
    { cond = condition; then_blk = then_block; else_blk = else_block;
      span = keyword.Token.span }

and parse_statement (parser : t) : Ast.stmt =
  match peek_kind parser with
  | Token.Kw_if -> parse_if parser
  | Token.Kw_while ->
      let keyword = advance parser in
      let condition = parse_expr parser in
      let body = parse_block parser in
      Ast.While { cond = condition; body; span = keyword.Token.span }
  | Token.Kw_for ->
      let keyword = advance parser in
      let loop_variable, _ = parse_ident parser "a loop variable" in
      ignore (expect parser Token.Kw_in "'in'");
      let lower_bound = parse_expr parser in
      ignore (expect parser Token.DotDotLt "'..<'");
      let upper_bound = parse_expr parser in
      let body = parse_block parser in
      Ast.For { var = loop_variable; lo = lower_bound; hi = upper_bound; body; span = keyword.Token.span }
  | Token.Kw_break -> let token = advance parser in Ast.Break token.Token.span
  | Token.Kw_continue -> let token = advance parser in Ast.Continue token.Token.span
  | Token.Kw_return ->
      let keyword = advance parser in
      (match peek_kind parser with
      | Token.Newline | Token.RBrace | Token.Eof -> Ast.Return (None, keyword.Token.span)
      | _ -> Ast.Return (Some (parse_expr parser), keyword.Token.span))
  | Token.Kw_let | Token.Kw_var ->
      let keyword = advance parser in
      let is_var = keyword.Token.kind = Token.Kw_var in
      let name, _ = parse_ident parser "identifier" in
      let annotation = parse_type_annotation parser in
      ignore (expect parser Token.Eq "'='");
      let value = parse_expr parser in
      Ast.Let
        { name; is_var; annot = annotation; value;
          span = span_between keyword.Token.span (Ast.expr_span value) }
  | Token.Ident name when peek_kind_at parser 1 = Token.Eq ->
      let identifier_token = advance parser in
      ignore (advance parser);
      let value = parse_expr parser in
      Ast.Assign { name; value; span = span_between identifier_token.Token.span (Ast.expr_span value) }
  (* `parser.x = expression` — a member assignment (concept 10); v0 handles one level (var.field) *)
  | Token.Ident obj when peek_kind_at parser 1 = Token.Dot && peek_kind_at parser 3 = Token.Eq ->
      let identifier_token = advance parser (* obj *) in
      ignore (advance parser (* . *));
      let field, _ = parse_ident parser "a member name" in
      ignore (advance parser (* = *));
      let value = parse_expr parser in
      Ast.Set_member { obj; field; value; span = span_between identifier_token.Token.span (Ast.expr_span value) }
  | _ ->
      let expression = parse_expr parser in
      Ast.Expr_stmt (expression, Ast.expr_span expression)

(* `( [label] name: Type , … )` — comma-separated parameters. The optional external label
   (Swift's `_ a: Int` for positional calls, or `ext a: Int`) is parsed and discarded; we
   call positionally and don't check labels (a simplification — see the explainer). *)
let parse_params (parser : t) : Ast.param list =
  ignore (expect parser Token.LParen "'('");
  if peek_kind parser = Token.RParen then (ignore (advance parser); [])
  else
    let rec loop accumulator =
      let first, _ = parse_ident parser "a parameter name" in
      (* `name :` -> label = name; `label name :` -> skip the external label, keep [name] *)
      let parameter_name = if peek_kind parser = Token.Colon then first else fst (parse_ident parser "a parameter name") in
      ignore (expect parser Token.Colon "':'");
      let parameter_type, _ = parse_ident parser "a parameter type" in
      let accumulator = { Ast.pname = parameter_name; ptype = parameter_type } :: accumulator in
      if peek_kind parser = Token.Comma then (ignore (advance parser); loop accumulator)
      else (ignore (expect parser Token.RParen "')'"); List.rev accumulator)
    in
    loop []

(* `func name ( params ) [ -> Type ] { body }` *)
let parse_function (parser : t) : Ast.func_decl =
  let keyword = advance parser (* func *) in
  let function_name, _ = parse_ident parser "a function name" in
  let parameters = parse_params parser in
  let return_type =
    if peek_kind parser = Token.Arrow then (
      ignore (advance parser);
      let type_name, _ = parse_ident parser "a return type" in
      Some type_name)
    else None
  in
  let body = parse_block parser in
  { Ast.fname = function_name; params = parameters; ret = return_type; body; fspan = keyword.Token.span }

(* `struct Name { (var|let) name: Type … }` — stored properties in order (concept 10) *)
let parse_struct (parser : t) : Ast.struct_decl =
  let keyword = advance parser (* struct *) in
  let struct_name, _ = parse_ident parser "a struct name" in
  ignore (expect parser Token.LBrace "'{'");
  let rec loop accumulator =
    while peek_kind parser = Token.Newline do ignore (advance parser) done;
    match peek_kind parser with
    | Token.RBrace -> ignore (advance parser); List.rev accumulator
    | Token.Eof -> ignore (expect parser Token.RBrace "'}'"); List.rev accumulator
    | Token.Kw_let | Token.Kw_var ->
        let is_variable = (advance parser).Token.kind = Token.Kw_var in
        let field_name, _ = parse_ident parser "a property name" in
        ignore (expect parser Token.Colon "':'");
        let field_type, _ = parse_ident parser "a property type" in
        (* a declaration ends at a newline or at the body's `}` — `{ var x: Int var y: Int }`
           is an error here as in Swift (`consecutive declarations on a line …`) *)
        (match peek_kind parser with
        | Token.Newline -> ignore (advance parser)
        | Token.RBrace | Token.Eof -> ()
        | _ -> Diagnostics.error parser.diagnostics (peek parser).Token.span "expected newline or end of declaration");
        loop ({ Ast.fld_name = field_name; fld_ty = field_type; fld_var = is_variable } :: accumulator)
    | _ ->
        let token = peek parser in
        Diagnostics.error parser.diagnostics token.Token.span "expected a stored property: 'var name: Type'";
        ignore (advance parser);
        loop accumulator
  in
  let fields = loop [] in
  { Ast.sname = struct_name; sfields = fields; sspan = keyword.Token.span }

(* A program is a sequence of top-level items: function declarations and statements. *)
let parse_program (parser : t) : Ast.program =
  let skip_newlines () = while peek_kind parser = Token.Newline do ignore (advance parser) done in
  let rec loop accumulator =
    skip_newlines ();
    match peek_kind parser with
    | Token.Eof -> { Ast.items = List.rev accumulator }
    | Token.Kw_func ->
        let function_decl = parse_function parser in
        (match peek_kind parser with
        | Token.Newline -> ignore (advance parser)
        | Token.Eof -> ()
        | _ -> Diagnostics.error parser.diagnostics (peek parser).Token.span "expected newline or end of statement");
        loop (Ast.IFunc function_decl :: accumulator)
    | Token.Kw_struct ->
        let struct_decl = parse_struct parser in
        (* a declaration ends at a newline or at the body's `}` — `{ var x: Int var y: Int }`
           is an error here as in Swift (`consecutive declarations on a line …`) *)
        (match peek_kind parser with
        | Token.Newline -> ignore (advance parser)
        | Token.RBrace | Token.Eof -> ()
        | _ -> Diagnostics.error parser.diagnostics (peek parser).Token.span "expected newline or end of declaration");
        loop (Ast.IStruct struct_decl :: accumulator)
    | _ ->
        let statement = parse_statement parser in
        (match peek_kind parser with
        | Token.Newline -> ignore (advance parser)
        | Token.Eof -> ()
        | _ -> Diagnostics.error parser.diagnostics (peek parser).Token.span "expected newline or end of statement");
        loop (Ast.IStmt statement :: accumulator)
  in
  loop []
