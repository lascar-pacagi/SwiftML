(* ANSWER KEY — concept 10 Sema: concepts 05–07 plus structs.

   New vs 07: a struct registry (PASS 0), member typing, the memberwise initializer's
   label/arity/type checks, member assignment (`p.x = e` needs a `var` binding AND a `var`
   field), and two guards for what the back end can lower: `==` is only defined on the scalar
   types, and `print` only takes them (swiftc prints any value — an honest divergence, §2).

   Inherited from 07:
     - a function-signature table built in a FIRST PASS (so calls, recursion, and forward
       references all resolve), then bodies checked in a second pass
     - call checking: arity + each argument against its parameter type; result = return type
     - return statements checked against the enclosing function's return type
     - the "missing return" check (a non-Void function must definitely return on every path)
     - functions are self-contained (params + the function table only — no top-level capture)
     - print and Void functions yield () (Types.TVoid)

   As from 05, the checker PRODUCES a `Tast.program`. Structs make the resolution concrete:
   `p.x` becomes a field INDEX, `Point(x: 1, y: 2)` becomes a `Struct_init` with its arguments
   in layout order and its labels discharged, and the layouts themselves travel to SILGen. None
   of that is re-derived downstream. PLAN.md §0.1. *)

let check (program : Ast.program) (diagnostics : Diagnostics.sink) : Tast.program option =
  let environment : (string * (Types.ty * bool)) list ref = ref [] in
  let loop_depth = ref 0 in
  let current_return_type : Types.ty option ref = ref None in
  let functions : (string, Types.ty list * Types.ty) Hashtbl.t =
    Hashtbl.create 16
  in
  let struct_layouts : (string, Types.struct_layout) Hashtbl.t =
    Hashtbl.create 16
  in
  let immutable_fields : (string * string, unit) Hashtbl.t =
    Hashtbl.create 16
  in
  (* (struct, `let` field) *)
  let report_error span message = Diagnostics.error diagnostics span message in
  let lookup_binding name = List.assoc_opt name !environment in
  let bind_name name binding = environment := (name, binding) :: !environment in
  let within_scope (action : unit -> unit) =
    let saved_environment = !environment in
    action ();
    environment := saved_environment
  in
  (* resolve a written type name: a builtin (Int/Bool/…) or a declared struct *)
  let resolve_type_opt name =
    match Types.of_name name with
    | Some resolved_type -> Some resolved_type
    | None ->
        if Hashtbl.mem struct_layouts name then Some (Types.TStruct name)
        else None
  in
  let resolve_type_silently name =
    Option.value (resolve_type_opt name) ~default:Types.TInt
  in
  let resolve_type span name =
    match resolve_type_opt name with
    | Some resolved_type -> resolved_type
    | None ->
        report_error span (Printf.sprintf "cannot find type '%s' in scope" name);
        Types.TInt
  in

  let make (e : Tast.expr_kind) (ty : Types.ty) (span : Token.span) : Tast.expr =
    { Tast.e; ty; span }
  in
  (* `%` is absent: Swift has no `%` on Double, so a tree containing one can never take it *)
  let rec is_int_literal = function
    | Ast.Int_lit _ -> true
    | Ast.Unary (Ast.Neg, expression, _) -> is_int_literal expression
    | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div), left, right, _) ->
        is_int_literal left && is_int_literal right
    | _ -> false
  in
  let common_operand_type left_expression left_type right_expression right_type
      : Types.ty option =
    if Types.equal left_type right_type then Some left_type
    else if is_int_literal left_expression && right_type = Types.TDouble then
      Some Types.TDouble
    else if is_int_literal right_expression && left_type = Types.TDouble then
      Some Types.TDouble
    else None
  in
  let rec infer_expression (expression : Ast.expr) : Tast.expr =
    match expression with
    | Ast.Int_lit (n, span) -> make (Tast.Int_lit n) Types.TInt span
    | Ast.Double_lit (f, span) -> make (Tast.Double_lit f) Types.TDouble span
    | Ast.Bool_lit (b, span) -> make (Tast.Bool_lit b) Types.TBool span
    | Ast.String_lit (t, span) -> make (Tast.String_lit t) Types.TString span
    | Ast.Var (variable_name, span) -> (
        match lookup_binding variable_name with
        | Some (variable_type, _) -> make (Tast.Local variable_name) variable_type span
        | None ->
            report_error span
              (Printf.sprintf "cannot find '%s' in scope" variable_name);
            make (Tast.Local variable_name) Types.TInt span)
    | Ast.Unary (Ast.Neg, operand_expression, span) ->
        let operand = infer_expression operand_expression in
        if not (Types.is_numeric operand.Tast.ty) then
          report_error span
            (Printf.sprintf
               "unary operator '-' cannot be applied to an operand of type '%s'"
               (Types.string_of_ty operand.Tast.ty));
        make (Tast.Unary (Ast.Neg, operand)) operand.Tast.ty span
    | Ast.Binary (operator, left_expression, right_expression, span) ->
        infer_binary operator left_expression right_expression span
    | Ast.Call (function_name, arguments, span) ->
        infer_call function_name arguments span
    (* `expression as T`: the type is written, so there is nothing to synthesise — CHECK the
       operand against it. The one arm where `infer_expression` calls `check_expr`. *)
    | Ast.Ascribe (operand_expression, type_name, span) -> (
        match Types.of_name type_name with
        | Some resolved_type ->
            make (Tast.Coerce (check_expr operand_expression resolved_type)) resolved_type span
        | None ->
            report_error span
              (Printf.sprintf "cannot find type '%s' in scope" type_name);
            let operand = infer_expression operand_expression in
            make (Tast.Coerce operand) operand.Tast.ty span)
    (* RESOLUTION: `p.x` becomes a field INDEX. The name was how the source spelled it; the
       position is what it means, and it is what SILGen needs. *)
    | Ast.Member (operand_expression, field_name, span) -> (
        let base = infer_expression operand_expression in
        let unresolved t =
          report_error span
            (Printf.sprintf "value of type '%s' has no member '%s'" t field_name);
          make (Tast.Field (base, 0, field_name)) Types.TInt span
        in
        match base.Tast.ty with
        | Types.TStruct struct_name -> (
            match Hashtbl.find_opt struct_layouts struct_name with
            | Some layout -> (
                match (Types.field_type layout field_name, Types.field_index layout field_name) with
                | Some field_type, Some index ->
                    make (Tast.Field (base, index, field_name)) field_type span
                | _ -> unresolved struct_name)
            | None -> make (Tast.Field (base, 0, field_name)) Types.TInt span)
        | base_type -> unresolved (Types.string_of_ty base_type))
  and infer_binary operator left_expression right_expression span : Tast.expr =
    let left = infer_expression left_expression and right = infer_expression right_expression in
    let left_type = left.Tast.ty and right_type = right.Tast.ty in
    let report_invalid_operands () =
      (* swiftc has two wordings and picks by whether the operands agree:
           1 < "a"      -> cannot be applied to operands of type 'Int' and 'String'
           true < false -> cannot be applied to two 'Bool' operands *)
      report_error span
        (if left_type = right_type then
           Printf.sprintf "binary operator '%s' cannot be applied to two '%s' operands"
             (Ast.string_of_binop operator) (Types.string_of_ty left_type)
         else
           Printf.sprintf
             "binary operator '%s' cannot be applied to operands of type '%s' and '%s'"
             (Ast.string_of_binop operator) (Types.string_of_ty left_type)
             (Types.string_of_ty right_type));
      Types.TInt
    in
    let common = common_operand_type left_expression left_type right_expression right_type in
    (* APPLY the solution: a side that flexed is re-checked AT the common type, so its literals
       come back carrying it. swiftc's CSApply, in miniature. *)
    let left, right =
      match common with
      | Some t ->
          ( (if Types.equal left_type t then left else check_expr left_expression t),
            if Types.equal right_type t then right else check_expr right_expression t )
      | None -> (left, right)
    in
    let result =
      match operator with
      | Ast.Add -> (
          match common with
          | Some ((Types.TInt | Types.TDouble) as common_type) -> common_type
          | Some Types.TString -> Types.TString
          | _ -> report_invalid_operands ())
      | Ast.Sub | Ast.Mul | Ast.Div -> (
          match common with
          | Some ((Types.TInt | Types.TDouble) as common_type) -> common_type
          | _ -> report_invalid_operands ())
      | Ast.Mod -> (
          match common with Some Types.TInt -> Types.TInt | _ -> report_invalid_operands ())
      | Ast.Eq | Ast.Ne -> (
          (* `==` on a struct needs an Equatable conformance (Exercise 3); swiftc rejects it with
             the two-operands wording, and so do we — the back end has no aggregate compare *)
          match common with
          | Some (Types.TInt | Types.TDouble | Types.TBool | Types.TString) -> Types.TBool
          | _ ->
              ignore (report_invalid_operands ());
              Types.TBool)
      | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge -> (
          match common with
          | Some (Types.TInt | Types.TDouble | Types.TString) -> Types.TBool
          | _ ->
              ignore (report_invalid_operands ());
              Types.TBool)
      | Ast.And | Ast.Or ->
          if left_type = Types.TBool && right_type = Types.TBool then Types.TBool
          else (
            ignore (report_invalid_operands ());
            Types.TBool)
    in
    make (Tast.Binary (operator, left, right)) result span
  and infer_call function_name arguments span : Tast.expr =
    (* RESOLUTION. `Ast.Call` is a struct initializer, a declared function, print, or an unknown
       name. Deciding is this function's job; the node records which. *)
    match Hashtbl.find_opt struct_layouts function_name with
    | Some layout ->
        infer_initializer function_name layout arguments
          span (* `Point(x: 1, y: 2)` — memberwise initializer *)
    | None -> (
        let argument_expressions = List.map snd arguments in
        let first ns = match ns with n :: _ -> n | [] -> make (Tast.Int_lit 0) Types.TInt span in
        match Hashtbl.find_opt functions function_name with
        | Some (parameter_types, return_type) ->
            let expected_count = List.length parameter_types
            and actual_count = List.length argument_expressions in
            if expected_count <> actual_count then (
              report_error span
                (Printf.sprintf "function '%s' expects %d argument(s) but %d given"
                   function_name expected_count actual_count);
              make (Tast.Fn_call (function_name, List.map infer_expression argument_expressions))
                return_type span)
            else
              make
                (Tast.Fn_call (function_name, List.map2 check_expr argument_expressions parameter_types))
                return_type span
        | None ->
            if function_name = "print" then
              match argument_expressions with
              | [ printed_expression ] ->
                  (* IRGen prints the scalar types only; swiftc would print `Point(x: 1, y: 2)` *)
                  let printed = infer_expression printed_expression in
                  (match printed.Tast.ty with
                  | Types.TInt | Types.TDouble | Types.TBool | Types.TString -> ()
                  | unsupported_type ->
                      report_error (Ast.expr_span printed_expression)
                        (Printf.sprintf
                           "cannot print a value of type '%s' (only Int, Double, Bool and String)"
                           (Types.string_of_ty unsupported_type)));
                  make (Tast.Print printed) Types.TVoid span
              | _ ->
                  report_error span "print(_:) expects exactly one argument";
                  make (Tast.Print (first (List.map infer_expression argument_expressions)))
                    Types.TVoid span
            else (
              report_error span (Printf.sprintf "cannot find '%s' in scope" function_name);
              make (Tast.Print (first (List.map infer_expression argument_expressions)))
                Types.TInt span))
  (* the memberwise initializer: one labeled argument per stored property, in order. The labels
     are checked here and then DISCHARGED — the resolved node keeps only the values, in layout
     order, because that is all the meaning a label carried. *)
  and infer_initializer struct_name (layout : Types.struct_layout)
      (arguments : Ast.arg list) span : Tast.expr =
    let fields = layout.Types.sl_fields in
    let values =
      if List.length arguments <> List.length fields then (
        report_error span
          (Printf.sprintf "'%s' initializer expects %d argument(s) but %d given" struct_name
             (List.length fields) (List.length arguments));
        List.map (fun (_, value) -> infer_expression value) arguments)
      else
        List.map2
          (fun (label, value) (field_name, field_type) ->
            (match label with
            | Some supplied_label when supplied_label <> field_name ->
                report_error (Ast.expr_span value)
                  (Printf.sprintf
                     "incorrect argument label in call (have '%s:', expected '%s:')"
                     supplied_label field_name)
            | None ->
                report_error (Ast.expr_span value)
                  (Printf.sprintf "missing argument label '%s:' in call" field_name)
            | _ -> ());
            check_expr value field_type)
          arguments fields
    in
    make (Tast.Struct_init (struct_name, values)) (Types.TStruct struct_name) span
  and check_expr (expression : Ast.expr) (expected : Types.ty) : Tast.expr =
    match expression with
    | Ast.Int_lit (n, span) ->
        (* the coercion, RECORDED: the node keeps its kind and takes the expected type, exactly
           as `swiftc -dump-ast` shows (`integer_literal_expr type="Double"`) *)
        if expected = Types.TInt || expected = Types.TDouble then
          make (Tast.Int_lit n) expected span
        else (
          report_error span
            (Printf.sprintf "cannot convert value of type 'Int' to specified type '%s'"
               (Types.string_of_ty expected));
          make (Tast.Int_lit n) Types.TInt span)
    | Ast.Binary
        (((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div) as operator), left_expression,
         right_expression, span)
      when Types.is_numeric expected ->
        make
          (Tast.Binary
             (operator, check_expr left_expression expected, check_expr right_expression expected))
          expected span
    | Ast.Binary (Ast.Mod, left_expression, right_expression, span) when expected = Types.TInt ->
        make
          (Tast.Binary
             (Ast.Mod, check_expr left_expression Types.TInt, check_expr right_expression Types.TInt))
          Types.TInt span
    | Ast.Unary (Ast.Neg, operand_expression, span) when Types.is_numeric expected ->
        make (Tast.Unary (Ast.Neg, check_expr operand_expression expected)) expected span
    | _ ->
        let actual = infer_expression expression in
        if not (Types.equal actual.Tast.ty expected) then
          report_error (Ast.expr_span expression)
            (Printf.sprintf "cannot convert value of type '%s' to specified type '%s'"
               (Types.string_of_ty actual.Tast.ty) (Types.string_of_ty expected));
        actual
  in
  (* does a block definitely return on every path? (the "missing return" check) — a question
     about the SOURCE shape, so it reads the Ast, not the tree being produced *)
  let rec statement_returns = function
    | Ast.Return _ -> true
    | Ast.If { then_blk; else_blk = Some expression; _ } ->
        block_returns then_blk && block_returns expression
    | _ -> false
  and block_returns statements =
    List.exists statement_returns statements
    (* the rest is unreachable *)
  in
  let rec check_statement (statement : Ast.stmt) : Tast.stmt =
    match statement with
    | Ast.Let { name; is_var; annot; value; span } ->
        let bound =
          match annot with
          | None -> infer_expression value
          | Some type_name -> (
              match resolve_type_opt type_name with
              | Some resolved_type -> check_expr value resolved_type
              | None ->
                  report_error span
                    (Printf.sprintf "cannot find type '%s' in scope" type_name);
                  infer_expression value)
        in
        bind_name name (bound.Tast.ty, is_var);
        Tast.Let { name; is_var; value = bound; span }
    | Ast.Assign { name; value; span } -> (
        match lookup_binding name with
        | None ->
            report_error span (Printf.sprintf "cannot find '%s' in scope" name);
            Tast.Assign { name; value = infer_expression value; span }
        | Some (binding_type, is_var) ->
            if not is_var then
              report_error span
                (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant" name);
            Tast.Assign { name; value = check_expr value binding_type; span })
    (* RESOLUTION again: the assigned field becomes an INDEX *)
    | Ast.Set_member { obj = object_name; field = field_name; value; span } -> (
        let unresolved t =
          report_error span
            (Printf.sprintf "value of type '%s' has no member '%s'" t field_name);
          Tast.Set_member
            { obj = object_name; field = 0; field_name; value = infer_expression value; span }
        in
        match lookup_binding object_name with
        | None ->
            report_error span (Printf.sprintf "cannot find '%s' in scope" object_name);
            Tast.Set_member
              { obj = object_name; field = 0; field_name; value = infer_expression value; span }
        | Some (Types.TStruct struct_name, is_var) -> (
            let layout = Hashtbl.find_opt struct_layouts struct_name in
            match
              ( Option.bind layout (fun l -> Types.field_type l field_name),
                Option.bind layout (fun l -> Types.field_index l field_name) )
            with
            | Some field_type, Some index ->
                (* swiftc's `diag::assignment_lhs_is_immutable_property`: the binding first, then
                   the field — a `let` field is immutable through every binding *)
                if not is_var then
                  report_error span
                    (Printf.sprintf "cannot assign to property: '%s' is a 'let' constant"
                       object_name)
                else if Hashtbl.mem immutable_fields (struct_name, field_name) then
                  report_error span
                    (Printf.sprintf "cannot assign to property: '%s' is a 'let' constant"
                       field_name);
                Tast.Set_member
                  { obj = object_name; field = index; field_name;
                    value = check_expr value field_type; span }
            | _ -> unresolved struct_name)
        | Some (base_type, _) -> unresolved (Types.string_of_ty base_type))
    | Ast.Expr_stmt (expression, _) -> Tast.Expr_stmt (infer_expression expression)
    | Ast.If { cond = condition; then_blk = then_block; else_blk = else_block; span } ->
        let cond = check_expr condition Types.TBool in
        let then_blk = check_block then_block in
        let else_blk = Option.map check_block else_block in
        Tast.If { cond; then_blk; else_blk; span }
    | Ast.While { cond = condition; body; span } ->
        let cond = check_expr condition Types.TBool in
        incr loop_depth;
        let body = check_block body in
        decr loop_depth;
        Tast.While { cond; body; span }
    | Ast.For { var = loop_variable; lo = lower_bound; hi = upper_bound; body; span } ->
        let lo = check_expr lower_bound Types.TInt in
        let hi = check_expr upper_bound Types.TInt in
        incr loop_depth;
        let checked_body = ref [] in
        within_scope (fun () ->
            bind_name loop_variable (Types.TInt, false);
            checked_body := List.map check_statement body);
        decr loop_depth;
        Tast.For { var = loop_variable; lo; hi; body = !checked_body; span }
    | Ast.Break span ->
        if !loop_depth = 0 then report_error span "'break' is only allowed inside a loop";
        Tast.Break span
    | Ast.Continue span ->
        if !loop_depth = 0 then report_error span "'continue' is only allowed inside a loop";
        Tast.Continue span
    | Ast.Return (returned_expression, span) -> (
        match !current_return_type with
        | None ->
            report_error span "return invalid outside of a func";
            Tast.Return (None, span)
        | Some return_type -> (
            match returned_expression with
            | Some expression ->
                if return_type = Types.TVoid then (
                  report_error span "unexpected non-void return value in void function";
                  Tast.Return (None, span))
                else Tast.Return (Some (check_expr expression return_type), span)
            | None ->
                if return_type <> Types.TVoid then
                  report_error span "non-void function should return a value";
                Tast.Return (None, span)))
  and check_block (statements : Ast.stmt list) : Tast.stmt list =
    let out = ref [] in
    within_scope (fun () -> out := List.map check_statement statements);
    !out
  in

  (* check one function body: a fresh scope with the parameters; then "missing return" *)
  let check_function (function_decl : Ast.func_decl) : Tast.func_decl =
    let return_type =
      match function_decl.Ast.ret with
      | None -> Types.TVoid
      | Some written_return_type -> resolve_type function_decl.Ast.fspan written_return_type
    in
    let saved_environment = !environment and saved_return_type = !current_return_type in
    environment := [];
    current_return_type := Some return_type;
    let params =
      List.map
        (fun (parameter : Ast.param) ->
          let pty = resolve_type function_decl.Ast.fspan parameter.Ast.ptype in
          bind_name parameter.Ast.pname (pty, false);
          { Tast.pname = parameter.Ast.pname; pty })
        function_decl.Ast.params
    in
    let body = List.map check_statement function_decl.Ast.body in
    environment := saved_environment;
    current_return_type := saved_return_type;
    if return_type <> Types.TVoid && not (block_returns function_decl.Ast.body) then
      report_error function_decl.Ast.fspan
        (Printf.sprintf "missing return in %s expected to return '%s'" "global function"
           (Types.string_of_ty return_type));
    { Tast.fname = function_decl.Ast.fname; params; ret = return_type; body;
      fspan = function_decl.Ast.fspan }
  in

  (* PASS 0: register struct names (so a field can reference another struct), then fill the
     layouts. Now any type name resolves and struct types are known to passes 1 and 2. *)
  List.iter
    (function
      | Ast.IStruct struct_decl ->
          if Hashtbl.mem struct_layouts struct_decl.Ast.sname then
            report_error struct_decl.Ast.sspan
              (Printf.sprintf "invalid redeclaration of '%s'"
                 struct_decl.Ast.sname);
          Hashtbl.replace struct_layouts struct_decl.Ast.sname
            { Types.sl_name = struct_decl.Ast.sname; sl_fields = [] }
      | _ -> ())
    program.Ast.items;
  List.iter
    (function
      | Ast.IStruct struct_decl ->
          let fields =
            List.map
              (fun (field : Ast.field) ->
                ( field.Ast.fld_name,
                  resolve_type struct_decl.Ast.sspan field.Ast.fld_ty ))
              struct_decl.Ast.sfields
          in
          List.iter
            (fun (field : Ast.field) ->
              if not field.Ast.fld_var then
                Hashtbl.replace immutable_fields
                  (struct_decl.Ast.sname, field.Ast.fld_name)
                  ())
            struct_decl.Ast.sfields;
          Hashtbl.replace struct_layouts struct_decl.Ast.sname
            { Types.sl_name = struct_decl.Ast.sname; sl_fields = fields }
      | _ -> ())
    program.Ast.items;
  (* PASS 1: collect signatures so calls/recursion/forward-references resolve. *)
  List.iter
    (function
      | Ast.IFunc function_decl ->
          if Hashtbl.mem functions function_decl.Ast.fname then
            report_error function_decl.Ast.fspan
              (Printf.sprintf "invalid redeclaration of '%s'"
                 function_decl.Ast.fname);
          let parameter_types =
            List.map
              (fun (parameter : Ast.param) ->
                resolve_type_silently parameter.Ast.ptype)
              function_decl.Ast.params
          in
          let return_type =
            match function_decl.Ast.ret with
            | None -> Types.TVoid
            | Some type_name -> resolve_type_silently type_name
          in
          Hashtbl.replace functions function_decl.Ast.fname
            (parameter_types, return_type)
      | _ -> ())
    program.Ast.items;
  (* PASS 2: check bodies and top-level statements, in order — producing the typed program. The
     struct LAYOUTS travel with it, so SILGen lowers the field order the checker checked. *)
  let items =
    List.map
      (function
        | Ast.IFunc function_decl -> Tast.IFunc (check_function function_decl)
        | Ast.IStmt statement -> Tast.IStmt (check_statement statement)
        | Ast.IStruct struct_decl ->
            Tast.IStruct (Hashtbl.find struct_layouts struct_decl.Ast.sname))
      program.Ast.items
  in
  if Diagnostics.has_errors diagnostics then None else Some { Tast.items }
