(* SILGen — concept 10 (skeleton). Carries Phase-2 SILGen complete; you add the STRUCT
   lowering (TODO(10g) member read, TODO(10h) member write). Lower the checked AST to SIL.

   Each variable becomes an `alloc_stack` slot, read with `load`, written with `store` (no
   SSA — Phase-4 mem2reg does that). Control flow becomes basic blocks: `if`/`while`/`for`
   build the CFG with `cond_br`/`br`; the AST tree becomes a graph. Each function lowers to
   its own SIL function; top-level statements become `main`. *)

type builder = {
  mutable next_value : int;
  mutable next_block : int;
  mutable current_block : Sil.block;
  mutable blocks : Sil.block list; (* all blocks, reverse creation order *)
  variables : (string, Sil.value) Hashtbl.t;
      (* variable name -> its alloc_stack address value *)
  value_types : (Sil.value, Types.ty) Hashtbl.t;
  functions : (string, Types.ty list * Types.ty) Hashtbl.t;
  struct_layouts : (string, Types.struct_layout) Hashtbl.t; (* concept 10 *)
  mutable loop_targets : (int * int) list;
      (* stack of (continue-target = header, break-target = exit) *)
}

(* --- the builder API (given) --- *)
let emit (builder : builder) (instruction : Sil.instr) (result_type : Types.ty)
    : Sil.value =
  let value = builder.next_value in
  builder.next_value <- value + 1;
  builder.current_block.Sil.instrs <-
    (value, instruction) :: builder.current_block.Sil.instrs;
  Hashtbl.replace builder.value_types value result_type;
  value

let new_block (builder : builder) : Sil.block =
  let block =
    { Sil.bid = builder.next_block; instrs = []; term = Sil.Unreachable }
  in
  builder.next_block <- builder.next_block + 1;
  builder.blocks <- block :: builder.blocks;
  block

let switch_to (builder : builder) (block : Sil.block) =
  builder.current_block <- block

let terminate (builder : builder) (terminator : Sil.term) =
  if builder.current_block.Sil.term = Sil.Unreachable then
    builder.current_block.Sil.term <- terminator

let value_type (builder : builder) (value : Sil.value) : Types.ty =
  Hashtbl.find builder.value_types value

(* an instruction with NO RESULT — `store`, `print`, a retain or release later on. `emit` still
   hands it a number (which is why the printed SIL skips one at a `store`: `%1 = alloc_stack`,
   `store %0 to %1`, then `%3 = load`), but there is nothing to name, so nothing comes back. *)
let emit_void (builder : builder) (instruction : Sil.instr) : unit =
  ignore (emit builder instruction Types.TVoid)

(* the same pair for `variables`: where a variable's slot is, and how a name comes to have one.
   `address_of` is total in practice — sema has already rejected the names that are not in scope. *)
let address_of (builder : builder) (name : string) : Sil.value =
  Hashtbl.find builder.variables name

let bind_variable (builder : builder) (name : string) (address : Sil.value) :
    unit =
  Hashtbl.replace builder.variables name address

(* the loop stack, innermost first. `break` and `continue` read it directly — in some concepts
   they need more out of the entry than a block id — but pushing and popping go through here, so
   the two targets are NAMED at the call site. They are not the same block: `continue` on a `for`
   must reach the latch that steps the counter, not the header that tests it. *)
let enter_loop (builder : builder) ~(continue_to : int) ~(break_to : int) : unit
    =
  builder.loop_targets <- (continue_to, break_to) :: builder.loop_targets

let leave_loop (builder : builder) : unit =
  builder.loop_targets <- List.tl builder.loop_targets

(* where `break` and `continue` go — the innermost loop's, since `loop_targets` is innermost-first.
   `None` means "not inside a loop", which sema has already rejected; the arm is the compiler's
   own safety net, not a case the source can reach. *)
let break_target (builder : builder) : int option =
  match builder.loop_targets with
  | (_, exit_target) :: _ -> Some exit_target
  | [] -> None

let continue_target (builder : builder) : int option =
  match builder.loop_targets with
  | (continue_target_id, _) :: _ -> Some continue_target_id
  | [] -> None

let result_type (operator : Ast.binop) (operand : Types.ty) : Types.ty =
  match operator with
  | Ast.Eq | Ast.Ne | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge | Ast.And | Ast.Or ->
      Types.TBool
  | Ast.Add | Ast.Sub | Ast.Mul | Ast.Div | Ast.Mod -> operand

(* --- lowering expressions: returns the SIL value holding the result --- *)

(* A block is a SCOPE for names. Without this, an inner `var x` would overwrite the outer `x`
   in `variables` and never give it back, so every later read of `x` would load the inner slot —
   `var x = 1; if c { var x = 2 }; print(x)` printing 2. Sema already checked the program under
   proper scoping; SILGen only has to stop its own table from leaking. *)
let restore_variables (builder : builder)
    (saved_variables : (string, Sil.value) Hashtbl.t) : unit =
  Hashtbl.reset builder.variables;
  Hashtbl.iter
    (fun name address -> Hashtbl.replace builder.variables name address)
    saved_variables

let rec gen_expr (builder : builder) (expression : Ast.expr) : Sil.value =
  match expression with
  | Ast.Int_lit (integer, _) -> emit builder (Sil.Int_lit integer) Types.TInt
  | Ast.Double_lit (number, _) ->
      emit builder (Sil.Float_lit number) Types.TDouble
  | Ast.Bool_lit (boolean, _) -> emit builder (Sil.Bool_lit boolean) Types.TBool
  | Ast.String_lit (text, _) -> emit builder (Sil.String_lit text) Types.TString
  (* `expression as T`: generate the operand AT the written type (see
     gen_expr_as). The `None` arm cannot be reached today — sema resolved this
     same name through `Types.of_name` and rejected it if it failed — but it is
     not dead weight either: an ascription with nothing to coerce lowers to its
     operand, which is what it does. Widening `as` to name a struct would start
     using it. *)
  | Ast.Ascribe (operand_expression, type_name, _) -> (
      match Types.of_name type_name with
      | Some resolved_type ->
          gen_expr_as builder operand_expression resolved_type
      | None -> gen_expr builder operand_expression)
  | Ast.Var (variable_name, _) ->
      let address = address_of builder variable_name in
      emit builder (Sil.Load address) (value_type builder address)
      (* the slot's element type *)
  | Ast.Unary (operator, operand_expression, _) ->
      let value = gen_expr builder operand_expression in
      emit builder (Sil.Unop (operator, value)) (value_type builder value)
  (* SHORT-CIRCUIT `&&` / `||` (concept 06 semantics, lowered here) — NOT
     bitwise: the right operand is evaluated only on the deciding edge, so its
     side effects (a trapping `a[i]` in `i < n && a[i]`, a force-unwrap, a
     throwing call) never run on the short path. Lowered to a cond_br diamond,
     the result is merged through a stack slot (mem2reg promotes it to a phi). *)
  | Ast.Binary
      (((Ast.And | Ast.Or) as operator), left_expression, right_expression, _)
    ->
      let left_value = gen_expr builder left_expression in
      (* the slot the two answers meet in — named for the operator it serves, since this arm
         lowers both. mem2reg turns it into a phi in Phase 4. *)
      let slot =
        emit builder
          (Sil.Alloc_stack (if operator = Ast.And then "$and" else "$or"))
          Types.TBool
      in
      emit_void builder (Sil.Store (left_value, slot));
      let right_block = new_block builder and merge_block = new_block builder in
      let true_target, false_target =
        if operator = Ast.And then (right_block.Sil.bid, merge_block.Sil.bid)
        else (merge_block.Sil.bid, right_block.Sil.bid)
      in
      terminate builder (Sil.Cond_br (left_value, true_target, false_target));
      switch_to builder right_block;
      let right_value = gen_expr builder right_expression in
      emit_void builder (Sil.Store (right_value, slot));
      terminate builder (Sil.Br merge_block.Sil.bid);
      switch_to builder merge_block;
      emit builder (Sil.Load slot) Types.TBool
  | Ast.Binary (operator, left_expression, right_expression, _) ->
      (* sema's `common_operand_type` lets an Int-literal tree adopt the other
         side's Double (`d * 2`, `2 * d`): that side must be generated AT
         Double, or IRGen emits `fmul double %d, 2` and clang rejects it.
         Re-generating a literal tree is safe — it has no side effects. *)
      let left_value = gen_expr builder left_expression in
      let right_value =
        if value_type builder left_value = Types.TDouble then
          gen_expr_as builder right_expression Types.TDouble
        else gen_expr builder right_expression
      in
      let left_value =
        if
          value_type builder right_value = Types.TDouble
          && value_type builder left_value = Types.TInt
        then gen_expr_as builder left_expression Types.TDouble
        else left_value
      in
      emit builder
        (Sil.Binop (operator, left_value, right_value))
        (result_type operator (value_type builder left_value))
  | Ast.Call (function_name, arguments, _) ->
      let argument_values =
        List.map (fun (_, expression) -> gen_expr builder expression) arguments
      in
      if Hashtbl.mem builder.struct_layouts function_name then
        emit builder (Sil.Struct argument_values) (Types.TStruct function_name)
        (* memberwise init *)
      else if Hashtbl.mem builder.functions function_name then
        let _, return_type = Hashtbl.find builder.functions function_name in
        let function_reference =
          emit builder (Sil.Func_ref function_name) return_type
        in
        emit builder
          (Sil.Apply (function_reference, argument_values))
          return_type
      else emit builder (Sil.Print (List.hd argument_values)) Types.TVoid
  | Ast.Member (operand_expression, field_name, _) ->
      (* TODO(10g): read a field out of a struct VALUE. The layout in
         [builder.struct_layouts] turns the field NAME into an index. §2. *)
      ignore (operand_expression, field_name);
      failwith "TODO(10g): lower member read (struct_extract)"

(* Generate [expression] AT an expected type. The only coercion this early is
   the integer literal that checks at Double: it must be BORN a Double, or the
   slot receives an i64 bit-pattern and `let d: Double = 1` reads back as
   4.94e-324. The recursion mirrors sema's `is_int_literal`. *)
and gen_expr_as (builder : builder) (expression : Ast.expr)
    (expected : Types.ty) : Sil.value =
  match (expression, expected) with
  | Ast.Int_lit (integer, _), Types.TDouble ->
      emit builder (Sil.Float_lit (float_of_int integer)) Types.TDouble
  | Ast.Unary (operator, operand_expression, _), Types.TDouble ->
      let value = gen_expr_as builder operand_expression Types.TDouble in
      emit builder (Sil.Unop (operator, value)) Types.TDouble
  | ( Ast.Binary
        ( ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div) as operator),
          left_expression,
          right_expression,
          _ ),
      Types.TDouble ) ->
      let left_value = gen_expr_as builder left_expression Types.TDouble
      and right_value = gen_expr_as builder right_expression Types.TDouble in
      emit builder (Sil.Binop (operator, left_value, right_value)) Types.TDouble
  | _ -> gen_expr builder expression

(* --- lowering statements; gen_block stops after a terminator (dead code) --- *)
let rec gen_block (builder : builder) (statements : Ast.stmt list) : unit =
  let saved_variables = Hashtbl.copy builder.variables in
  let rec go statements =
    match statements with
    | [] -> ()
    | statement :: rest ->
        gen_stmt builder statement;
        if builder.current_block.Sil.term = Sil.Unreachable then go rest
  in
  go statements;
  restore_variables builder saved_variables

and gen_stmt (builder : builder) (statement : Ast.stmt) : unit =
  match statement with
  | Ast.Let { name; annot; value; _ } ->
      (* an annotation makes the slot that type, and the value is generated AT it *)
      let value =
        match annot with
        | Some type_name -> (
            match Types.of_name type_name with
            | Some resolved_type -> gen_expr_as builder value resolved_type
            | None -> gen_expr builder value)
        | None -> gen_expr builder value
      in
      let address =
        emit builder (Sil.Alloc_stack name) (value_type builder value)
      in
      bind_variable builder name address;
      emit_void builder (Sil.Store (value, address))
  | Ast.Assign { name; value; _ } ->
      let value = gen_expr builder value in
      emit_void builder (Sil.Store (value, address_of builder name))
  | Ast.Set_member { obj = object_name; field = field_name; value; _ } ->
      (* TODO(10h): `p.x = expression` — where VALUE SEMANTICS lives. Write
         THROUGH p's own slot (address of the field, then store), which is why
         assigning to p.x can never be observed through a copy q. §2. *)
      ignore (object_name, field_name, value);
      failwith "TODO(10h): lower member write (struct_element_addr + store)"
  | Ast.Expr_stmt (expression, _) -> ignore (gen_expr builder expression)
  | Ast.Return (return_expression, _) -> (
      match return_expression with
      | Some expression ->
          let value = gen_expr builder expression in
          terminate builder (Sil.Return (Some value))
      | None -> terminate builder (Sil.Return None))
  | Ast.If
      {
        cond = condition;
        then_blk = then_block_statements;
        else_blk = else_block_statements;
        _;
      } ->
      let condition_value = gen_expr builder condition in
      let then_block = new_block builder in
      let merge_block = new_block builder in
      let else_block =
        match else_block_statements with
        | Some _ -> new_block builder
        | None -> merge_block
      in
      terminate builder
        (Sil.Cond_br (condition_value, then_block.Sil.bid, else_block.Sil.bid));
      switch_to builder then_block;
      gen_block builder then_block_statements;
      terminate builder (Sil.Br merge_block.Sil.bid);
      (match else_block_statements with
      | Some statements ->
          switch_to builder else_block;
          gen_block builder statements;
          terminate builder (Sil.Br merge_block.Sil.bid)
      | None -> ());
      switch_to builder merge_block
  | Ast.While { cond = condition; body; _ } ->
      let header = new_block builder
      and body_block = new_block builder
      and exit_block = new_block builder in
      terminate builder (Sil.Br header.Sil.bid);
      switch_to builder header;
      let condition_value = gen_expr builder condition in
      terminate builder
        (Sil.Cond_br (condition_value, body_block.Sil.bid, exit_block.Sil.bid));
      switch_to builder body_block;
      enter_loop builder ~continue_to:header.Sil.bid
        ~break_to:exit_block.Sil.bid;
      gen_block builder body;
      terminate builder (Sil.Br header.Sil.bid);
      leave_loop builder;
      switch_to builder exit_block
  | Ast.For { var = loop_variable; lo = lower_bound; hi = upper_bound; body; _ }
    ->
      (* desugar `for value in lo ..< hi { body }` into a counted while loop *)
      let lower_bound_value = gen_expr builder lower_bound in
      let upper_bound_value = gen_expr builder upper_bound in
      let address = emit builder (Sil.Alloc_stack loop_variable) Types.TInt in
      bind_variable builder loop_variable address;
      emit_void builder (Sil.Store (lower_bound_value, address));
      (* header -> body -> latch (the increment) -> header; continue jumps to the latch so
         it doesn't skip `value = value + 1` (that would loop forever) *)
      let header = new_block builder and body_block = new_block builder in
      let latch = new_block builder and exit_block = new_block builder in
      terminate builder (Sil.Br header.Sil.bid);
      switch_to builder header;
      let current_value = emit builder (Sil.Load address) Types.TInt in
      let condition_value =
        emit builder
          (Sil.Binop (Ast.Lt, current_value, upper_bound_value))
          Types.TBool
      in
      terminate builder
        (Sil.Cond_br (condition_value, body_block.Sil.bid, exit_block.Sil.bid));
      switch_to builder body_block;
      enter_loop builder ~continue_to:latch.Sil.bid ~break_to:exit_block.Sil.bid;
      gen_block builder body;
      terminate builder (Sil.Br latch.Sil.bid);
      leave_loop builder;
      switch_to builder latch;
      let counter_value = emit builder (Sil.Load address) Types.TInt in
      let one = emit builder (Sil.Int_lit 1) Types.TInt in
      let incremented_value =
        emit builder (Sil.Binop (Ast.Add, counter_value, one)) Types.TInt
      in
      emit_void builder (Sil.Store (incremented_value, address));
      terminate builder (Sil.Br header.Sil.bid);
      switch_to builder exit_block
  | Ast.Break _ -> (
      match break_target builder with
      | Some exit_target -> terminate builder (Sil.Br exit_target)
      | None -> ())
  | Ast.Continue _ -> (
      match continue_target builder with
      | Some target -> terminate builder (Sil.Br target)
      | None -> ())

(* --- lowering a function: params get slots; then the body --- *)
let lower_func struct_layouts functions (name : string)
    (parameters : (string * Types.ty) list) (return_type : Types.ty)
    (body : Ast.stmt list) : Sil.func =
  let value_types = Hashtbl.create 16 in
  let entry_block = { Sil.bid = 0; instrs = []; term = Sil.Unreachable } in
  let builder =
    {
      next_value = 0;
      next_block = 1;
      current_block = entry_block;
      blocks = [ entry_block ];
      variables = Hashtbl.create 16;
      value_types;
      functions;
      struct_layouts;
      loop_targets = [];
    }
  in
  (* parameters are the function's first SIL values %0..%(n-1) *)
  let sil_parameters =
    List.map
      (fun (_, parameter_type) ->
        let parameter_value = builder.next_value in
        builder.next_value <- parameter_value + 1;
        Hashtbl.replace value_types parameter_value parameter_type;
        (parameter_value, parameter_type))
      parameters
  in
  (* store each parameter into a stack slot so the body's load/store is uniform *)
  List.iter2
    (fun (parameter_value, parameter_type) (parameter_name, _) ->
      let address =
        emit builder (Sil.Alloc_stack parameter_name) parameter_type
      in
      bind_variable builder parameter_name address;
      emit_void builder (Sil.Store (parameter_value, address)))
    sil_parameters parameters;
  gen_block builder body;
  terminate builder
    (if return_type = Types.TVoid then Sil.Return None else Sil.Unreachable);
  {
    Sil.fname = name;
    params = sil_parameters;
    ret = return_type;
    blocks = builder.blocks;
    val_ty = value_types;
  }

(* --- the entry point: a checked program -> a SIL module --- *)
let lower (program : Ast.program) : Sil.modul =
  (* struct registry first (names, then layouts) so any type name resolves *)
  let struct_layouts : (string, Types.struct_layout) Hashtbl.t =
    Hashtbl.create 16
  in
  List.iter
    (function
      | Ast.IStruct struct_decl ->
          Hashtbl.replace struct_layouts struct_decl.Ast.sname
            { Types.sl_name = struct_decl.Ast.sname; sl_fields = [] }
      | _ -> ())
    program.Ast.items;
  let type_of_name name =
    match Types.of_name name with
    | Some resolved_type -> resolved_type
    | None ->
        if Hashtbl.mem struct_layouts name then Types.TStruct name
        else Types.TInt
  in
  List.iter
    (function
      | Ast.IStruct struct_decl ->
          let fields =
            List.map
              (fun (field : Ast.field) ->
                (field.Ast.fld_name, type_of_name field.Ast.fld_ty))
              struct_decl.Ast.sfields
          in
          Hashtbl.replace struct_layouts struct_decl.Ast.sname
            { Types.sl_name = struct_decl.Ast.sname; sl_fields = fields }
      | _ -> ())
    program.Ast.items;
  let return_type_of function_decl =
    match function_decl.Ast.ret with
    | None -> Types.TVoid
    | Some type_name -> type_of_name type_name
  in
  let functions = Hashtbl.create 16 in
  List.iter
    (function
      | Ast.IFunc function_decl ->
          let parameter_types =
            List.map
              (fun (parameter : Ast.param) -> type_of_name parameter.Ast.ptype)
              function_decl.Ast.params
          in
          Hashtbl.replace functions function_decl.Ast.fname
            (parameter_types, return_type_of function_decl)
      | _ -> ())
    program.Ast.items;
  let function_definitions =
    List.filter_map
      (function
        | Ast.IFunc function_decl ->
            let parameters =
              List.map
                (fun (parameter : Ast.param) ->
                  (parameter.Ast.pname, type_of_name parameter.Ast.ptype))
                function_decl.Ast.params
            in
            Some
              (lower_func struct_layouts functions function_decl.Ast.fname
                 parameters
                 (return_type_of function_decl)
                 function_decl.Ast.body)
        | _ -> None)
      program.Ast.items
  in
  let main_statements =
    List.filter_map
      (function Ast.IStmt statement -> Some statement | _ -> None)
      program.Ast.items
  in
  let main =
    lower_func struct_layouts functions "main" [] Types.TVoid main_statements
  in
  let ordered_struct_layouts =
    List.filter_map
      (function
        | Ast.IStruct struct_decl ->
            Some (Hashtbl.find struct_layouts struct_decl.Ast.sname)
        | _ -> None)
      program.Ast.items
  in
  {
    Sil.funcs = function_definitions @ [ main ];
    structs = ordered_struct_layouts;
  }
