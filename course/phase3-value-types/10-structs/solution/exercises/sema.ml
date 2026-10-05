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
   of that is re-derived downstream. PLAN.md §0.1.

   WITH §6 EXERCISES APPLIED — all three are lowered HERE, to ordinary functions, so SILGen
   and IRGen see nothing new but an argument passed by address:
     EX1  a method `m` of `S` becomes the function `S.m` with `self` as its first parameter;
          `recv.m(args)` becomes `Fn_call ("S.m", recv :: args)`. A `mutating` method takes
          `self` by ADDRESS (`pinout`), and its receiver must be a mutable variable, passed as
          `Address_of`. Inside a method a bare field or method name means `self.name`.
     EX2  a computed property `p` of `S` becomes the getter function `S.p`, and reading `x.p`
          becomes a call to it. It has no storage, so the layout keeps only the stored fields.
     EX3  `struct S: Equatable` gets a synthesized `S.__eq`, the `&&` of its fields' `==`;
          `a == b` calls it and `a != b` compares that call with `false`. Without the
          conformance, `==` on a struct is still rejected, as swiftc rejects it. *)

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
  (* the fields declared with `let`, as (struct name, field name) pairs: a write to one
     is refused through every binding, `var` or not *)
  let immutable_fields : (string * string, unit) Hashtbl.t =
    Hashtbl.create 16
  in
  (* EX1: (struct, method) -> mutating?, parameter types, return type *)
  let methods : (string * string, bool * Types.ty list * Types.ty) Hashtbl.t =
    Hashtbl.create 16
  in
  (* EX2: (struct, computed property) -> its type *)
  let computed_properties : (string * string, Types.ty) Hashtbl.t = Hashtbl.create 16 in
  (* EX3: the structs that declared `: Equatable`, and the `==` functions made so far *)
  let equatable_structs : (string, unit) Hashtbl.t = Hashtbl.create 16 in
  let synthesized : Tast.item list ref = ref [] in
  (* EX1: inside a method body, the struct it belongs to and whether it is `mutating` *)
  let current_self : (string * bool) option ref = ref None in
  let function_name_of struct_name member = struct_name ^ "." ^ member in
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
    (* an unknown name resolves to TError, never a guess: see Types.equal *)
    Option.value (resolve_type_opt name) ~default:Types.TError
  in
  let resolve_type span name =
    match resolve_type_opt name with
    | Some resolved_type -> resolved_type
    | None ->
        report_error span (Printf.sprintf "cannot find type '%s' in scope" name);
        Types.TError
  in

  let make (e : Tast.expr_kind) (ty : Types.ty) (span : Token.span) : Tast.expr =
    { Tast.e; ty; span }
  in
  (* Given the span of a member expression such as `point.z`, return the span of just its
     field name, the `z`. Report a bad member with it, so the error points at the name, as
     in swiftc. *)
  let member_name_span (span : Token.span) (name : string) : Token.span =
    let length = String.length name in
    { span with
      Token.lo =
        { span.Token.hi with
          Token.col = span.Token.hi.Token.col - length;
          offset = span.Token.hi.Token.offset - length } }
  in
  (* EX1: inside a method, an unbound [name] that is a stored or computed property (or, with
     [~as_method], a method) of the struct means `self.name` *)
  let self_member ?(as_method = false) name =
    match !current_self with
    | Some (struct_name, _) when lookup_binding name = None ->
        if as_method then Hashtbl.mem methods (struct_name, name)
        else
          Hashtbl.mem computed_properties (struct_name, name)
          || (match Hashtbl.find_opt struct_layouts struct_name with
             | Some layout -> Types.field_index layout name <> None
             | None -> false)
    | _ -> false
  in
  (* EX3: the synthesized `S.__eq (a, b)`: true when every field compares equal. A field of
     another struct type compares through that struct's own `__eq`. *)
  let rec equality_function struct_name =
    let name = function_name_of struct_name "__eq" in
    if not (List.exists
              (function Tast.IFunc f -> f.Tast.fname = name | _ -> false)
              !synthesized)
    then (
      let layout = Hashtbl.find struct_layouts struct_name in
      let struct_type = Types.TStruct struct_name and span = Token.dummy_span in
      let side parameter = make (Tast.Local parameter) struct_type span in
      let field_equal index (field_name, field_type) =
        let read parameter = make (Tast.Field (side parameter, index, field_name)) field_type span in
        match field_type with
        | Types.TStruct inner ->
            make (Tast.Fn_call (equality_function inner, [ read "a"; read "b" ])) Types.TBool span
        | _ -> make (Tast.Binary (Ast.Eq, read "a", read "b")) Types.TBool span
      in
      let comparison =
        match List.mapi field_equal layout.Types.sl_fields with
        | [] -> make (Tast.Bool_lit true) Types.TBool span
        | first :: rest ->
            List.fold_left
              (fun so_far next -> make (Tast.Binary (Ast.And, so_far, next)) Types.TBool span)
              first rest
      in
      synthesized :=
        !synthesized
        @ [ Tast.IFunc
              {
                Tast.fname = name;
                params =
                  [ { Tast.pname = "a"; pty = struct_type; pinout = false };
                    { Tast.pname = "b"; pty = struct_type; pinout = false } ];
                ret = Types.TBool;
                body = [ Tast.Return (Some comparison, span) ];
                fspan = span;
              } ]);
    name
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
    | Ast.Var (variable_name, span) when self_member variable_name ->
        infer_expression (Ast.Member (Ast.Var ("self", span), variable_name, span))
    | Ast.Var (variable_name, span) -> (
        match lookup_binding variable_name with
        | Some (variable_type, _) -> make (Tast.Local variable_name) variable_type span
        | None ->
            report_error span
              (Printf.sprintf "cannot find '%s' in scope" variable_name);
            make (Tast.Local variable_name) Types.TError span)
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
            make (Tast.Coerce (infer_expression operand_expression)) Types.TError span)
    (* RESOLUTION: `p.x` becomes a field INDEX. The name was how the source spelled it; the
       position is what it means, and it is what SILGen needs. *)
    | Ast.Member (operand_expression, field_name, span) -> (
        let base = infer_expression operand_expression in
        let unresolved t =
          report_error (member_name_span span field_name)
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
                | _ -> (
                    (* EX2: a computed property reads by calling its getter *)
                    match Hashtbl.find_opt computed_properties (struct_name, field_name) with
                    | Some property_type ->
                        make
                          (Tast.Fn_call (function_name_of struct_name field_name, [ base ]))
                          property_type span
                    | None -> unresolved struct_name))
            | None -> make (Tast.Field (base, 0, field_name)) Types.TInt span)
        (* a member of something already reported is as unknown as it is *)
        | Types.TError -> make (Tast.Field (base, 0, field_name)) Types.TError span
        | base_type -> unresolved (Types.string_of_ty base_type))
    | Ast.Method_call (receiver, method_name, arguments, span) ->
        infer_method_call receiver method_name arguments span
  (* EX1: `recv.m(args)` is a call to `S.m` with the receiver first — a copy for an ordinary
     method, the receiver's ADDRESS for a `mutating` one, so the method's writes land in it *)
  and infer_method_call receiver method_name arguments span : Tast.expr =
    let base = infer_expression receiver in
    let argument_expressions = List.map snd arguments in
    let unchecked return_type =
      make
        (Tast.Fn_call (method_name, base :: List.map infer_expression argument_expressions))
        return_type span
    in
    match base.Tast.ty with
    | Types.TStruct struct_name -> (
        match Hashtbl.find_opt methods (struct_name, method_name) with
        | None ->
            report_error span
              (Printf.sprintf "value of type '%s' has no member '%s'" struct_name method_name);
            unchecked Types.TError
        | Some (is_mutating, parameter_types, return_type) ->
            if List.length parameter_types <> List.length argument_expressions then (
              report_error span
                (Printf.sprintf "method '%s' expects %d argument(s) but %d given" method_name
                   (List.length parameter_types) (List.length argument_expressions));
              unchecked return_type)
            else
              let checked = List.map2 check_expr argument_expressions parameter_types in
              let self_argument =
                if is_mutating then mutable_receiver receiver base else base
              in
              make
                (Tast.Fn_call (function_name_of struct_name method_name, self_argument :: checked))
                return_type span)
    | Types.TError -> unchecked Types.TError
    | other ->
        report_error span
          (Printf.sprintf "value of type '%s' has no member '%s'" (Types.string_of_ty other)
             method_name);
        unchecked Types.TError
  (* EX1: the receiver of a `mutating` call must be storage that can change: a `var`, or a
     path of `var` fields inside one. Its address is what is passed. *)
  and mutable_receiver receiver base : Tast.expr =
    let refuse why =
      report_error (Ast.expr_span receiver)
        ("cannot use mutating member on immutable value: " ^ why);
      base
    in
    let rec path expression =
      match expression with
      | Ast.Var (name, span) when self_member name ->
          path (Ast.Member (Ast.Var ("self", span), name, span))
      | Ast.Var (name, _) -> (
          match lookup_binding name with
          | Some (Types.TStruct struct_name, is_var) ->
              if is_var then Ok (name, [], struct_name)
              else if name = "self" then Error "'self' is immutable"
              else Error (Printf.sprintf "'%s' is a 'let' constant" name)
          | _ -> Error (Printf.sprintf "'%s' is not a struct variable" name))
      | Ast.Member (inner, field_name, _) -> (
          match path inner with
          | Error _ as error -> error
          | Ok (root, indices, struct_name) -> (
              let layout = Hashtbl.find struct_layouts struct_name in
              match (Types.field_index layout field_name, Types.field_type layout field_name) with
              | Some index, Some (Types.TStruct inner_struct) ->
                  if Hashtbl.mem immutable_fields (struct_name, field_name) then
                    Error (Printf.sprintf "'%s' is a 'let' constant" field_name)
                  else Ok (root, indices @ [ index ], inner_struct)
              | _ -> Error (Printf.sprintf "'%s' is not a stored struct property" field_name)))
      | Ast.Call (function_name, _, _) | Ast.Method_call (_, function_name, _, _) ->
          Error (Printf.sprintf "'%s' returns immutable value" function_name)
      | _ -> Error "it is not a variable"
    in
    match path receiver with
    | Ok (root, indices, _) -> make (Tast.Address_of (root, indices)) base.Tast.ty base.Tast.span
    | Error why -> refuse why
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
    match (operator, common) with
    | (Ast.Eq | Ast.Ne), Some (Types.TStruct struct_name)
      when Hashtbl.mem equatable_structs struct_name ->
        (* EX3: the synthesized `==`; `!=` is its result compared with false *)
        let equal =
          make (Tast.Fn_call (equality_function struct_name, [ left; right ])) Types.TBool span
        in
        if operator = Ast.Eq then equal
        else
          make
            (Tast.Binary (Ast.Eq, equal, make (Tast.Bool_lit false) Types.TBool span))
            Types.TBool span
    | _ ->
    let result =
      (* an operand whose type was already reported says nothing about this operator: a
         comparison or `&&` is still a Bool, anything else is as unknown as its operand *)
      if left_type = Types.TError || right_type = Types.TError then
        match operator with
        | Ast.Eq | Ast.Ne | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge | Ast.And | Ast.Or ->
            Types.TBool
        | Ast.Add | Ast.Sub | Ast.Mul | Ast.Div | Ast.Mod -> Types.TError
      else
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
    if self_member ~as_method:true function_name then
      (* EX1: inside a method, `m(args)` is `self.m(args)` *)
      infer_method_call (Ast.Var ("self", span)) function_name arguments span
    else
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
                  | Types.TError | Types.TInt | Types.TDouble | Types.TBool | Types.TString -> ()
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
                Types.TError span))
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
        else if expected = Types.TError then make (Tast.Int_lit n) Types.TInt span
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
        (* the name is bound at the type the programmer WROTE, so `let x: Nope = true`
           makes `x` a TError, not a Bool that every later use would then contradict *)
        let bound, bound_type =
          match annot with
          | None ->
              let bound = infer_expression value in
              (bound, bound.Tast.ty)
          | Some type_name -> (
              match resolve_type_opt type_name with
              | Some resolved_type -> (check_expr value resolved_type, resolved_type)
              | None ->
                  report_error span
                    (Printf.sprintf "cannot find type '%s' in scope" type_name);
                  (infer_expression value, Types.TError))
        in
        bind_name name (bound_type, is_var);
        Tast.Let { name; is_var; value = bound; span }
    | Ast.Assign { name; value; span } when self_member name ->
        (* EX1: inside a method, `x = e` for a property x is `self.x = e` *)
        check_statement (Ast.Set_member { obj = "self"; field = name; value; span })
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
                    (if object_name = "self" then
                       (* EX1: `self` in a method that is not `mutating` *)
                       "cannot assign to property: 'self' is immutable"
                     else
                       Printf.sprintf "cannot assign to property: '%s' is a 'let' constant"
                         object_name)
                else if Hashtbl.mem immutable_fields (struct_name, field_name) then
                  report_error span
                    (Printf.sprintf "cannot assign to property: '%s' is a 'let' constant"
                       field_name);
                Tast.Set_member
                  { obj = object_name; field = index; field_name;
                    value = check_expr value field_type; span }
            | _ when Hashtbl.mem computed_properties (struct_name, field_name) ->
                (* EX2: a computed property has a getter and nothing to store into *)
                report_error span
                  (Printf.sprintf "cannot assign to property: '%s' is a get-only property"
                     field_name);
                Tast.Set_member
                  { obj = object_name; field = 0; field_name; value = infer_expression value;
                    span }
            | _ -> unresolved struct_name)
        | Some (Types.TError, _) ->
            Tast.Set_member
              { obj = object_name; field = 0; field_name;
                value = check_expr value Types.TError; span }
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
  let check_function ?(kind = "global function") ?(self_parameter : (string * bool) option)
      (function_decl : Ast.func_decl) : Tast.func_decl =
    let return_type =
      match function_decl.Ast.ret with
      | None -> Types.TVoid
      | Some written_return_type -> resolve_type function_decl.Ast.fspan written_return_type
    in
    let saved_environment = !environment and saved_return_type = !current_return_type in
    environment := [];
    current_return_type := Some return_type;
    (* EX1: a method's `self` comes first — mutable, and passed by address, if `mutating` *)
    let self_params =
      match self_parameter with
      | None -> []
      | Some (struct_name, is_mutating) ->
          bind_name "self" (Types.TStruct struct_name, is_mutating);
          [ { Tast.pname = "self"; pty = Types.TStruct struct_name; pinout = is_mutating } ]
    in
    let saved_self = !current_self in
    current_self := self_parameter;
    let params =
      self_params
      @ List.map
          (fun (parameter : Ast.param) ->
            let pty = resolve_type function_decl.Ast.fspan parameter.Ast.ptype in
            bind_name parameter.Ast.pname (pty, false);
            { Tast.pname = parameter.Ast.pname; pty; pinout = false })
          function_decl.Ast.params
    in
    let body = List.map check_statement function_decl.Ast.body in
    environment := saved_environment;
    current_return_type := saved_return_type;
    current_self := saved_self;
    (* `-> Nope` was reported already; what it should return is unknown, so is whether
       the body returns it *)
    if return_type <> Types.TVoid && return_type <> Types.TError
       && not (block_returns function_decl.Ast.body) then
      report_error function_decl.Ast.fspan
        (Printf.sprintf "missing return in %s expected to return '%s'" kind
           (Types.string_of_ty return_type));
    let fname =
      match self_parameter with
      | Some (struct_name, _) -> function_name_of struct_name function_decl.Ast.fname
      | None -> function_decl.Ast.fname
    in
    { Tast.fname; params; ret = return_type; body; fspan = function_decl.Ast.fspan }
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
  (* EX1-EX3: each struct's methods, computed properties and conformances, now that every type
     name resolves *)
  List.iter
    (function
      | Ast.IStruct struct_decl ->
          let struct_name = struct_decl.Ast.sname in
          let layout = Hashtbl.find struct_layouts struct_name in
          let member_taken name =
            Types.field_index layout name <> None
            || Hashtbl.mem methods (struct_name, name)
            || Hashtbl.mem computed_properties (struct_name, name)
          in
          List.iter
            (fun (method_decl : Ast.method_decl) ->
              let f = method_decl.Ast.mfunc in
              if member_taken f.Ast.fname then
                report_error f.Ast.fspan
                  (Printf.sprintf "invalid redeclaration of '%s'" f.Ast.fname);
              Hashtbl.replace methods (struct_name, f.Ast.fname)
                ( method_decl.Ast.mutating,
                  List.map (fun (p : Ast.param) -> resolve_type_silently p.Ast.ptype)
                    f.Ast.params,
                  match f.Ast.ret with
                  | None -> Types.TVoid
                  | Some type_name -> resolve_type_silently type_name ))
            struct_decl.Ast.smethods;
          List.iter
            (fun (property : Ast.computed) ->
              if member_taken property.Ast.cname then
                report_error property.Ast.cspan
                  (Printf.sprintf "invalid redeclaration of '%s'" property.Ast.cname);
              Hashtbl.replace computed_properties (struct_name, property.Ast.cname)
                (resolve_type property.Ast.cspan property.Ast.cty))
            struct_decl.Ast.scomputed;
          List.iter
            (fun protocol_name ->
              if protocol_name = "Equatable" then
                Hashtbl.replace equatable_structs struct_name ()
              else
                report_error struct_decl.Ast.sspan
                  (Printf.sprintf "cannot find type '%s' in scope" protocol_name))
            struct_decl.Ast.sconforms
      | _ -> ())
    program.Ast.items;
  (* EX3: synthesis needs every stored property to be Equatable itself, as in swiftc *)
  List.iter
    (function
      | Ast.IStruct struct_decl when Hashtbl.mem equatable_structs struct_decl.Ast.sname ->
          let layout = Hashtbl.find struct_layouts struct_decl.Ast.sname in
          let field_equatable (_, field_type) =
            match field_type with
            | Types.TInt | Types.TDouble | Types.TBool | Types.TString | Types.TError -> true
            | Types.TStruct inner -> Hashtbl.mem equatable_structs inner
            | _ -> false
          in
          if not (List.for_all field_equatable layout.Types.sl_fields) then
            report_error struct_decl.Ast.sspan
              (Printf.sprintf "type '%s' does not conform to protocol 'Equatable'"
                 struct_decl.Ast.sname)
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
    List.concat_map
      (function
        | Ast.IFunc function_decl -> [ Tast.IFunc (check_function function_decl) ]
        | Ast.IStmt statement -> [ Tast.IStmt (check_statement statement) ]
        | Ast.IStruct struct_decl ->
            let struct_name = struct_decl.Ast.sname in
            (* EX1: each method is a function with `self` first *)
            let method_functions =
              List.map
                (fun (method_decl : Ast.method_decl) ->
                  Tast.IFunc
                    (check_function ~kind:"instance method"
                       ~self_parameter:(struct_name, method_decl.Ast.mutating)
                       method_decl.Ast.mfunc))
                struct_decl.Ast.smethods
            in
            (* EX2: each computed property is a getter: a method with no parameters *)
            let getters =
              List.map
                (fun (property : Ast.computed) ->
                  Tast.IFunc
                    (check_function ~kind:"getter" ~self_parameter:(struct_name, false)
                       {
                         Ast.fname = property.Ast.cname;
                         params = [];
                         ret = Some property.Ast.cty;
                         body = property.Ast.cbody;
                         fspan = property.Ast.cspan;
                       }))
                struct_decl.Ast.scomputed
            in
            (Tast.IStruct (Hashtbl.find struct_layouts struct_name) :: method_functions)
            @ getters)
      program.Ast.items
  in
  (* EX3: the `==` functions synthesized while checking *)
  let items = items @ !synthesized in
  if Diagnostics.has_errors diagnostics then None else Some { Tast.items }
