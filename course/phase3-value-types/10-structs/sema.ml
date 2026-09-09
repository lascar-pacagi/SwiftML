(* Sema — concept 10 skeleton: concepts 05–07 are complete; you add structs.

   New vs 07: a struct registry, member typing, the memberwise initializer's
   label/arity/type checks, member assignment (`p.x = expression` needs a `var` binding AND a `var`
   field), and two guards for what the back end can lower: `==` is only defined on scalar
   types, and `print` only takes them (swiftc prints any value — an honest divergence, §2).

   Inherited from 07:
     - a function-signature table built in a FIRST PASS (so calls, recursion, and forward
       references all resolve), then bodies checked in a second pass
     - call checking: arity + each argument against its parameter type; result = return type
     - return statements checked against the enclosing function's return type
     - the "missing return" check (a non-Void function must definitely return on every path)
     - functions are self-contained (params + the function table only — no top-level capture)
     - print and Void functions yield () (Types.TVoid) *)

let check (program : Ast.program) (diagnostics : Diagnostics.sink) : unit =
  let environment : (string * (Types.ty * bool)) list ref = ref [] in
  let loop_depth = ref 0 in
  let current_return_type : Types.ty option ref = ref None in
  let functions : (string, Types.ty list * Types.ty) Hashtbl.t = Hashtbl.create 16 in
  let struct_layouts : (string, Types.struct_layout) Hashtbl.t = Hashtbl.create 16 in
  let immutable_fields : (string * string, unit) Hashtbl.t = Hashtbl.create 16 in (* (struct, `let` field) *)
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
    | None -> if Hashtbl.mem struct_layouts name then Some (Types.TStruct name) else None
  in
  let resolve_type_silently name = Option.value (resolve_type_opt name) ~default:Types.TInt in
  let resolve_type span name =
    match resolve_type_opt name with
    | Some resolved_type -> resolved_type
    | None ->
        report_error span (Printf.sprintf "cannot find type '%s' in scope" name);
        Types.TInt
  in

  let rec is_int_literal = function
    | Ast.Int_lit _ -> true
    | Ast.Unary (Ast.Neg, expression, _) -> is_int_literal expression
    | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div | Ast.Mod), left, right, _) ->
        is_int_literal left && is_int_literal right
    | _ -> false
  in
  let common_operand_type left_expression left_type right_expression right_type : Types.ty option =
    if Types.equal left_type right_type then Some left_type
    else if is_int_literal left_expression && right_type = Types.TDouble then Some Types.TDouble
    else if is_int_literal right_expression && left_type = Types.TDouble then Some Types.TDouble
    else None
  in
  let rec infer_expression (expression : Ast.expr) : Types.ty =
    match expression with
    | Ast.Int_lit _ -> Types.TInt
    | Ast.Double_lit _ -> Types.TDouble
    | Ast.Bool_lit _ -> Types.TBool
    | Ast.String_lit _ -> Types.TString
    | Ast.Var (variable_name, span) -> (
        match lookup_binding variable_name with
        | Some (variable_type, _) -> variable_type
        | None ->
            report_error span (Printf.sprintf "cannot find '%s' in scope" variable_name);
            Types.TInt)
    | Ast.Unary (Ast.Neg, operand_expression, span) ->
        let operand_type = infer_expression operand_expression in
        if Types.is_numeric operand_type then operand_type
        else (
          report_error span
            (Printf.sprintf "unary operator '-' cannot be applied to an operand of type '%s'"
               (Types.string_of_ty operand_type));
          operand_type)
    | Ast.Binary (operator, left_expression, right_expression, span) -> infer_binary operator left_expression right_expression span
    | Ast.Call (function_name, arguments, span) -> infer_call function_name arguments span
    (* `expression as T`: the type is written, so there is nothing to synthesise — CHECK the
       operand against it. The one arm where `infer_expression` calls `check_expr`. *)
    | Ast.Ascribe (operand_expression, type_name, span) -> (
        match Types.of_name type_name with
        | Some resolved_type ->
            check_expr operand_expression resolved_type;
            resolved_type
        | None ->
            report_error span (Printf.sprintf "cannot find type '%s' in scope" type_name);
            infer_expression operand_expression)
    | Ast.Member (operand_expression, field_name, span) ->
        ignore (operand_expression, field_name, span);
        (* TODO(10e): infer_expression the base, require a struct, and look up the field type in its
           registered layout. Diagnose both an unknown field and a scalar base (§2). *)
        failwith "TODO(10e): type-check a member read"
  and infer_binary operator left_expression right_expression span : Types.ty =
    let left_type = infer_expression left_expression and right_type = infer_expression right_expression in
    let report_invalid_operands () =
      (* swiftc has two wordings and picks by whether the operands agree:
           1 < "a"      -> cannot be applied to operands of type 'Int' and 'String'
           true < false -> cannot be applied to two 'Bool' operands *)
      report_error span
        (if left_type = right_type then
           Printf.sprintf "binary operator '%s' cannot be applied to two '%s' operands"
             (Ast.string_of_binop operator) (Types.string_of_ty left_type)
         else
           Printf.sprintf "binary operator '%s' cannot be applied to operands of type '%s' and '%s'"
             (Ast.string_of_binop operator) (Types.string_of_ty left_type) (Types.string_of_ty right_type));
      Types.TInt
    in
    match operator with
    | Ast.Add -> (
        match common_operand_type left_expression left_type right_expression right_type with
        | Some ((Types.TInt | Types.TDouble) as common_type) -> common_type
        | Some Types.TString -> Types.TString
        | _ -> report_invalid_operands ())
    | Ast.Sub | Ast.Mul | Ast.Div -> (
        match common_operand_type left_expression left_type right_expression right_type with Some ((Types.TInt | Types.TDouble) as common_type) -> common_type | _ -> report_invalid_operands ())
    | Ast.Mod -> ( match common_operand_type left_expression left_type right_expression right_type with Some Types.TInt -> Types.TInt | _ -> report_invalid_operands ())
    | Ast.Eq | Ast.Ne -> (
        (* `==` on a struct needs an Equatable conformance (Exercise 3); swiftc rejects it with
           the two-operands wording, and so do we — the back end has no aggregate compare *)
        match common_operand_type left_expression left_type right_expression right_type with
        | Some (Types.TInt | Types.TDouble | Types.TBool | Types.TString) -> Types.TBool
        | _ -> ignore (report_invalid_operands ()); Types.TBool)
    | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge -> (
        match common_operand_type left_expression left_type right_expression right_type with
        | Some (Types.TInt | Types.TDouble | Types.TString) -> Types.TBool
        | _ -> ignore (report_invalid_operands ()); Types.TBool)
    | Ast.And | Ast.Or ->
        if left_type = Types.TBool && right_type = Types.TBool then Types.TBool else (ignore (report_invalid_operands ()); Types.TBool)
  and infer_call function_name arguments span : Types.ty =
    match Hashtbl.find_opt struct_layouts function_name with
    | Some layout -> infer_initializer function_name layout arguments span (* `Point(x: 1, y: 2)` — memberwise initializer *)
    | None -> (
        let argument_expressions = List.map snd arguments in
        match Hashtbl.find_opt functions function_name with
        | Some (parameter_types, return_type) ->
            let expected_count = List.length parameter_types and actual_count = List.length argument_expressions in
            if expected_count <> actual_count then
              report_error span (Printf.sprintf "function '%s' expects %d argument(s) but %d given" function_name expected_count actual_count)
            else List.iter2 (fun argument parameter_type -> check_expr argument parameter_type) argument_expressions parameter_types;
            return_type
        | None ->
            if function_name = "print" then (
              (match argument_expressions with
              | [ printed_expression ] -> (
                  (* IRGen prints the scalar types only; swiftc would print `Point(x: 1, y: 2)` *)
                  match infer_expression printed_expression with
                  | Types.TInt | Types.TDouble | Types.TBool | Types.TString -> ()
                  | unsupported_type ->
                      report_error (Ast.expr_span printed_expression)
                        (Printf.sprintf "cannot print a value of type '%s' (only Int, Double, Bool and String)"
                           (Types.string_of_ty unsupported_type)))
              | _ ->
                  report_error span "print(_:) expects exactly one argument";
                  List.iter (fun argument -> ignore (infer_expression argument)) argument_expressions);
              Types.TVoid)
            else (
              report_error span (Printf.sprintf "cannot find '%s' in scope" function_name);
              List.iter (fun argument -> ignore (infer_expression argument)) argument_expressions;
              Types.TInt))
  (* the memberwise initializer: one labeled argument per stored property, in order *)
  and infer_initializer struct_name (layout : Types.struct_layout) (arguments : Ast.arg list) span : Types.ty =
    ignore (layout, arguments, span);
    (* TODO(10e): check arity, then each label and value type against the corresponding
       stored property. A successful initializer has type [TStruct struct_name]. *)
    failwith ("TODO(10e): type-check memberwise initialization of " ^ struct_name)
  and check_expr (expression : Ast.expr) (expected : Types.ty) : unit =
    match expression with
    | Ast.Int_lit _ ->
        if expected = Types.TInt || expected = Types.TDouble then ()
        else
          report_error (Ast.expr_span expression)
            (Printf.sprintf "cannot convert value of type 'Int' to specified type '%s'"
               (Types.string_of_ty expected))
    | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div), left_expression, right_expression, _) when Types.is_numeric expected ->
        check_expr left_expression expected;
        check_expr right_expression expected
    | Ast.Binary (Ast.Mod, left_expression, right_expression, _) when expected = Types.TInt ->
        check_expr left_expression Types.TInt;
        check_expr right_expression Types.TInt
    | Ast.Unary (Ast.Neg, operand_expression, _) when Types.is_numeric expected -> check_expr operand_expression expected
    | _ ->
        let actual_type = infer_expression expression in
        if not (Types.equal actual_type expected) then
          report_error (Ast.expr_span expression)
            (Printf.sprintf "cannot convert value of type '%s' to specified type '%s'"
               (Types.string_of_ty actual_type) (Types.string_of_ty expected))
  in
  (* does a block definitely return on every path? (the "missing return" check) *)
  let rec statement_returns = function
    | Ast.Return _ -> true
    | Ast.If { then_blk; else_blk = Some expression; _ } -> block_returns then_blk && block_returns expression
    | _ -> false
  and block_returns statements = List.exists statement_returns statements (* the rest is unreachable *) in
  let rec check_statement (statement : Ast.stmt) : unit =
    match statement with
    | Ast.Let { name; is_var; annot; value; span } ->
        let binding_type =
          match annot with
          | None -> infer_expression value
          | Some type_name -> (
              match resolve_type_opt type_name with
              | Some resolved_type -> check_expr value resolved_type; resolved_type
              | None -> report_error span (Printf.sprintf "cannot find type '%s' in scope" type_name); infer_expression value)
        in
        bind_name name (binding_type, is_var)
    | Ast.Assign { name; value; span } -> (
        match lookup_binding name with
        | None -> report_error span (Printf.sprintf "cannot find '%s' in scope" name); ignore (infer_expression value)
        | Some (binding_type, is_var) ->
            if not is_var then
              report_error span (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant" name);
            check_expr value binding_type)
    | Ast.Set_member { obj; field; value; span } ->
        ignore (obj, field, value, span);
        (* TODO(10f): resolve the binding and field, reject a [let] binding or [let] field,
           and check the assigned value against the field type (§2). *)
        failwith "TODO(10f): type-check a member write"
    | Ast.Expr_stmt (expression, _) -> ignore (infer_expression expression)
    | Ast.If { cond = condition; then_blk = then_block; else_blk = else_block; _ } ->
        check_expr condition Types.TBool;
        check_block then_block;
        Option.iter check_block else_block
    | Ast.While { cond = condition; body; _ } ->
        check_expr condition Types.TBool;
        incr loop_depth; check_block body; decr loop_depth
    | Ast.For { var = loop_variable; lo = lower_bound; hi = upper_bound; body; _ } ->
        check_expr lower_bound Types.TInt;
        check_expr upper_bound Types.TInt;
        incr loop_depth;
        within_scope (fun () -> bind_name loop_variable (Types.TInt, false); List.iter check_statement body);
        decr loop_depth
    | Ast.Break span -> if !loop_depth = 0 then report_error span "'break' is only allowed inside a loop"
    | Ast.Continue span -> if !loop_depth = 0 then report_error span "'continue' is only allowed inside a loop"
    | Ast.Return (returned_expression, span) -> (
        match !current_return_type with
        | None -> report_error span "return invalid outside of a func"
        | Some return_type -> (
            match returned_expression with
            | Some expression ->
                if return_type = Types.TVoid then
                  report_error span "unexpected non-void return value in void function"
                else check_expr expression return_type
            | None ->
                if return_type <> Types.TVoid then report_error span "non-void function should return a value"))
  and check_block (statements : Ast.stmt list) : unit = within_scope (fun () -> List.iter check_statement statements) in

  (* check one function body: a fresh scope with the parameters; then "missing return" *)
  let check_function (function_decl : Ast.func_decl) : unit =
    let return_type =
      match function_decl.Ast.ret with
      | None -> Types.TVoid
      | Some written_return_type -> resolve_type function_decl.Ast.fspan written_return_type
    in
    let saved_environment = !environment and saved_return_type = !current_return_type in
    environment := [];
    current_return_type := Some return_type;
    List.iter
      (fun (parameter : Ast.param) -> bind_name parameter.Ast.pname (resolve_type function_decl.Ast.fspan parameter.Ast.ptype, false))
      function_decl.Ast.params;
    List.iter check_statement function_decl.Ast.body;
    environment := saved_environment;
    current_return_type := saved_return_type;
    if return_type <> Types.TVoid && not (block_returns function_decl.Ast.body) then
      report_error function_decl.Ast.fspan
        (Printf.sprintf "missing return in %s expected to return '%s'" "global function" (Types.string_of_ty return_type))
  in

  (* TODO(10d): register every struct name first, then resolve and install its ordered field
     layout. The two passes allow a field to name a struct declared later. Record [let]
     fields in [immutable_fields], and diagnose duplicate struct names (§2). *)
  let register_structs () =
    if List.exists (function Ast.IStruct _ -> true | _ -> false) program.Ast.items then
      failwith "TODO(10d): register struct layouts"
  in
  register_structs ();
  (* PASS 1: collect signatures so calls/recursion/forward-references resolve. *)
  List.iter
    (function
      | Ast.IFunc function_decl ->
          if Hashtbl.mem functions function_decl.Ast.fname then
            report_error function_decl.Ast.fspan (Printf.sprintf "invalid redeclaration of '%s'" function_decl.Ast.fname);
          let parameter_types = List.map (fun (parameter : Ast.param) -> resolve_type_silently parameter.Ast.ptype) function_decl.Ast.params in
          let return_type = match function_decl.Ast.ret with None -> Types.TVoid | Some type_name -> resolve_type_silently type_name in
          Hashtbl.replace functions function_decl.Ast.fname (parameter_types, return_type)
      | _ -> ())
    program.Ast.items;
  (* PASS 2: check bodies and top-level statements, in order. *)
  List.iter
    (function
      | Ast.IFunc function_decl -> check_function function_decl
      | Ast.IStmt statement -> check_statement statement
      | Ast.IStruct _ -> ())
    program.Ast.items
