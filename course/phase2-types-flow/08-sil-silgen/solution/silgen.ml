(* FROZEN SOLUTION — concept 08 SILGen: lower the (checked) AST to raw, memory-based SIL.

   Each variable becomes an `alloc_stack` slot, read with `load`, written with `store` (no
   SSA — Phase-4 mem2reg does that). Control flow becomes basic blocks: `if`/`while`/`for`
   build the CFG with `cond_br`/`br`; the AST tree becomes a graph. Each function lowers to
   its own SIL function; top-level statements become `main`. *)

(* The builder — SILGen's entire working state, and the thing to understand before writing any
   lowering. Generating SIL is a walk over the AST that APPENDS instructions to one block at a
   time, so most of these fields answer "where am I writing, and what have I written so far".
   SIL names things positionally — values `%0`, `%1`, … and blocks `bb0`, `bb1`, … numbered per
   function — which is what the two counters hand out. *)
type builder = {
  mutable next_value : int; (* the next %n *)
  mutable next_block : int; (* the next bbN *)
  mutable current_block : Sil.block;
      (* THE CURSOR: `emit` appends here, and `switch_to` moves it *)
  mutable blocks : Sil.block list;
      (* every block made, newest first; `lower` reverses at the end *)
  variables : (string, Sil.value) Hashtbl.t;
      (* variable name -> the ADDRESS of its alloc_stack slot *)
  value_types : (Sil.value, Types.ty) Hashtbl.t;
      (* the type of every value emitted; read with `value_type` *)
  functions : (string, Types.ty list * Types.ty) Hashtbl.t;
      (* signatures, so a call knows its result *)
  mutable loops : (int * int) list;
      (* innermost first: (where `continue` goes, where `break` goes) *)
}

(* --- the builder API (given) ---
   `emit` appends an instruction to the CURRENT block, numbers its result, remembers that
   result's type, and hands the value back — so lowering an expression is a chain of `emit`s
   whose values feed each other. `new_block` makes a block and registers it, but deliberately
   does NOT move the cursor: creating a block and starting to write into it are separate
   decisions, and control flow needs them apart. `switch_to` is the move. `terminate` sets the
   current block's terminator and only the FIRST one sticks — a `return` inside a branch has
   already ended that block, so a `br` emitted after it is correctly ignored rather than
   overwriting the return. `value_type` reads a value's type back out. *)
let emit (builder : builder) (instruction : Sil.instr) (ty : Types.ty) :
    Sil.value =
  let value = builder.next_value in
  builder.next_value <- value + 1;
  builder.current_block.Sil.instrs <-
    (value, instruction) :: builder.current_block.Sil.instrs;
  Hashtbl.replace builder.value_types value ty;
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

let terminate (builder : builder) (t : Sil.term) =
  if builder.current_block.Sil.term = Sil.Unreachable then
    builder.current_block.Sil.term <- t

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

let bind_variable (builder : builder) (name : string) (addr : Sil.value) : unit
    =
  Hashtbl.replace builder.variables name addr

(* the loop stack, innermost first. `break` and `continue` read it directly — in some concepts
   they need more out of the entry than a block id — but pushing and popping go through here, so
   the two targets are NAMED at the call site. They are not the same block: `continue` on a `for`
   must reach the latch that steps the counter, not the header that tests it. *)
let enter_loop (builder : builder) ~(continue_to : int) ~(break_to : int) : unit
    =
  builder.loops <- (continue_to, break_to) :: builder.loops

let leave_loop (builder : builder) : unit =
  builder.loops <- List.tl builder.loops

(* where `break` and `continue` go — the innermost loop's, since `loops` is innermost-first.
   `None` means "not inside a loop", which sema has already rejected; the arm is the compiler's
   own safety net, not a case the source can reach. *)
let break_target (builder : builder) : int option =
  match builder.loops with
  | (_, exit_target) :: _ -> Some exit_target
  | [] -> None

let continue_target (builder : builder) : int option =
  match builder.loops with
  | (continue_target_id, _) :: _ -> Some continue_target_id
  | [] -> None

let result_type (op : Ast.binop) (operand : Types.ty) : Types.ty =
  match op with
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
    (fun k value -> Hashtbl.replace builder.variables k value)
    saved_variables

let rec gen_expression (builder : builder) (expression : Ast.expr) : Sil.value =
  match expression with
  | Ast.Int_lit (n, _) -> emit builder (Sil.Int_lit n) Types.TInt
  | Ast.Double_lit (number, _) ->
      emit builder (Sil.Float_lit number) Types.TDouble
  | Ast.Bool_lit (boolean, _) -> emit builder (Sil.Bool_lit boolean) Types.TBool
  | Ast.String_lit (text, _) -> emit builder (Sil.String_lit text) Types.TString
  (* `e as T`: generate the operand AT the written type (see
     gen_expression_as). The `None` arm cannot
     be reached today — sema resolved this same name through `Types.of_name` and rejected it if it
     failed — but it is not dead weight either: an ascription with nothing to coerce lowers to its
     operand, which is what it does. Widening `as` to name a struct would start using it. *)
  | Ast.Ascribe (operand_expression, tyname, _) -> (
      match Types.of_name tyname with
      | Some t -> gen_expression_as builder operand_expression t
      | None -> gen_expression builder operand_expression)
  | Ast.Var (name, _) ->
      let addr = address_of builder name in
      emit builder (Sil.Load addr) (value_type builder addr)
      (* the slot's element type *)
  | Ast.Unary (op, operand_expression, _) ->
      let value = gen_expression builder operand_expression in
      emit builder (Sil.Unop (op, value)) (value_type builder value)
  (* SHORT-CIRCUIT `&&` / `||` (concept 06 semantics, lowered here) — NOT
     bitwise: the right operand is evaluated only on the deciding edge, so its
     side effects (a trapping `a[i]` in `i < n && a[i]`,
     a force-unwrap, a throwing call) never run on the short path. Lowered to a cond_br diamond, the
     result merged through a stack slot (mem2reg promotes it to a phi). *)
  | Ast.Binary (((Ast.And | Ast.Or) as op), left_expression, right_expression, _)
    ->
      let left_value = gen_expression builder left_expression in
      (* the slot the two answers meet in — named for the operator it serves, since this arm
         lowers both. mem2reg turns it into a phi in Phase 4. *)
      let slot =
        emit builder
          (Sil.Alloc_stack (if op = Ast.And then "$and" else "$or"))
          Types.TBool
      in
      emit_void builder (Sil.Store (left_value, slot));
      let right_block = new_block builder and merge_block = new_block builder in
      let then_target, else_target =
        if op = Ast.And then (right_block.Sil.bid, merge_block.Sil.bid)
        else (merge_block.Sil.bid, right_block.Sil.bid)
      in
      terminate builder (Sil.Cond_br (left_value, then_target, else_target));
      switch_to builder right_block;
      let right_value = gen_expression builder right_expression in
      emit_void builder (Sil.Store (right_value, slot));
      terminate builder (Sil.Br merge_block.Sil.bid);
      switch_to builder merge_block;
      emit builder (Sil.Load slot) Types.TBool
  | Ast.Binary (op, left_expression, right_expression, _) ->
      let left_value = gen_expression builder left_expression
      and right_value = gen_expression builder right_expression in
      let operand =
        if
          value_type builder left_value = Types.TDouble
          || value_type builder right_value = Types.TDouble
        then Types.TDouble
        else value_type builder left_value
      in
      emit builder
        (Sil.Binop (op, left_value, right_value))
        (result_type op operand)
  | Ast.Call (function_name, arguments, _) ->
      let argument_values = List.map (gen_expression builder) arguments in
      if Hashtbl.mem builder.functions function_name then
        let _, ret = Hashtbl.find builder.functions function_name in
        let function_reference =
          emit builder (Sil.Func_ref function_name) ret
        in
        emit builder (Sil.Apply (function_reference, argument_values)) ret
      else emit builder (Sil.Print (List.hd argument_values)) Types.TVoid

(* Generate [expression] AT an expected type. The only coercion this early is
   the integer literal that
   checks at Double: it must be BORN a Double, or the slot receives an i64 bit-pattern and
   `let d: Double = 1` reads back as 4.94e-324. The recursion mirrors sema's `is_int_literal`. *)
and gen_expression_as (builder : builder) (expression : Ast.expr)
    (expected : Types.ty) : Sil.value =
  match (expression, expected) with
  | Ast.Int_lit (n, _), Types.TDouble ->
      emit builder (Sil.Float_lit (float_of_int n)) Types.TDouble
  | Ast.Unary (op, operand_expression, _), Types.TDouble ->
      let value = gen_expression_as builder operand_expression Types.TDouble in
      emit builder (Sil.Unop (op, value)) Types.TDouble
  | ( Ast.Binary
        ( ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div) as op),
          left_expression,
          right_expression,
          _ ),
      Types.TDouble ) ->
      let left_value = gen_expression_as builder left_expression Types.TDouble
      and right_value =
        gen_expression_as builder right_expression Types.TDouble
      in
      emit builder (Sil.Binop (op, left_value, right_value)) Types.TDouble
  | _ -> gen_expression builder expression

(* --- lowering statements; gen_block stops after a terminator (dead code) --- *)
let rec gen_block (builder : builder) (statements : Ast.stmt list) : unit =
  let saved_variables = Hashtbl.copy builder.variables in
  let rec go statements =
    match statements with
    | [] -> ()
    | s :: rest ->
        gen_statement builder s;
        if builder.current_block.Sil.term = Sil.Unreachable then go rest
  in
  go statements;
  restore_variables builder saved_variables

and gen_statement (builder : builder) (s : Ast.stmt) : unit =
  match s with
  | Ast.Let { name; annot; value; _ } ->
      (* an annotation makes the slot that type, and the value is generated AT it *)
      let value =
        match annot with
        | Some n -> (
            match Types.of_name n with
            | Some t -> gen_expression_as builder value t
            | None -> gen_expression builder value)
        | None -> gen_expression builder value
      in
      let addr =
        emit builder (Sil.Alloc_stack name) (value_type builder value)
      in
      bind_variable builder name addr;
      emit_void builder (Sil.Store (value, addr))
  | Ast.Assign { name; value; _ } ->
      let value = gen_expression builder value in
      emit_void builder (Sil.Store (value, address_of builder name))
  | Ast.Expr_stmt (expression, _) -> ignore (gen_expression builder expression)
  | Ast.Return (eo, _) -> (
      match eo with
      | Some expression ->
          let value = gen_expression builder expression in
          terminate builder (Sil.Return (Some value))
      | None -> terminate builder (Sil.Return None))
  | Ast.If { cond; then_blk; else_blk; _ } ->
      let condition_value = gen_expression builder cond in
      let then_block = new_block builder in
      let merge_block = new_block builder in
      let else_block =
        match else_blk with Some _ -> new_block builder | None -> merge_block
      in
      terminate builder
        (Sil.Cond_br (condition_value, then_block.Sil.bid, else_block.Sil.bid));
      switch_to builder then_block;
      gen_block builder then_blk;
      terminate builder (Sil.Br merge_block.Sil.bid);
      (match else_blk with
      | Some expression ->
          switch_to builder else_block;
          gen_block builder expression;
          terminate builder (Sil.Br merge_block.Sil.bid)
      | None -> ());
      switch_to builder merge_block
  | Ast.While { cond; body; _ } ->
      let header = new_block builder
      and body_block = new_block builder
      and exit_block = new_block builder in
      terminate builder (Sil.Br header.Sil.bid);
      switch_to builder header;
      let condition_value = gen_expression builder cond in
      terminate builder
        (Sil.Cond_br (condition_value, body_block.Sil.bid, exit_block.Sil.bid));
      switch_to builder body_block;
      enter_loop builder ~continue_to:header.Sil.bid
        ~break_to:exit_block.Sil.bid;
      gen_block builder body;
      terminate builder (Sil.Br header.Sil.bid);
      leave_loop builder;
      switch_to builder exit_block
  | Ast.For { var; lo; hi; body; _ } ->
      (* desugar `for v in lo ..< hi { body }` into a counted while loop *)
      let lower_value = gen_expression builder lo in
      let upper_value = gen_expression builder hi in
      let addr = emit builder (Sil.Alloc_stack var) Types.TInt in
      bind_variable builder var addr;
      emit_void builder (Sil.Store (lower_value, addr));
      (* header -> body -> latch (the increment) -> header; continue jumps to the latch so
         it doesn't skip `v = v + 1` (that would loop forever) *)
      let header = new_block builder and body_block = new_block builder in
      let latch = new_block builder and exit_block = new_block builder in
      terminate builder (Sil.Br header.Sil.bid);
      switch_to builder header;
      let current_value = emit builder (Sil.Load addr) Types.TInt in
      let condition_value =
        emit builder
          (Sil.Binop (Ast.Lt, current_value, upper_value))
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
      let current_value = emit builder (Sil.Load addr) Types.TInt in
      let one = emit builder (Sil.Int_lit 1) Types.TInt in
      let incremented_value =
        emit builder (Sil.Binop (Ast.Add, current_value, one)) Types.TInt
      in
      emit_void builder (Sil.Store (incremented_value, addr));
      terminate builder (Sil.Br header.Sil.bid);
      switch_to builder exit_block
  | Ast.Break _ -> (
      match break_target builder with
      | Some exit_target -> terminate builder (Sil.Br exit_target)
      | None -> ())
  | Ast.Continue _ -> (
      match continue_target builder with
      | Some condition_value -> terminate builder (Sil.Br condition_value)
      | None -> ())

(* --- lowering a function: params get slots; then the body --- *)
let lower_func functions (name : string) (params : (string * Types.ty) list)
    (ret : Types.ty) (body : Ast.stmt list) : Sil.func =
  let value_types = Hashtbl.create 16 in
  let entry = { Sil.bid = 0; instrs = []; term = Sil.Unreachable } in
  let builder =
    {
      next_value = 0;
      next_block = 1;
      current_block = entry;
      blocks = [ entry ];
      variables = Hashtbl.create 16;
      value_types;
      functions;
      loops = [];
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
      params
  in
  (* store each parameter into a stack slot so the body's load/store is uniform *)
  List.iter2
    (fun (parameter_value, parameter_type) (parameter_name, _) ->
      let addr = emit builder (Sil.Alloc_stack parameter_name) parameter_type in
      bind_variable builder parameter_name addr;
      emit_void builder (Sil.Store (parameter_value, addr)))
    sil_parameters params;
  gen_block builder body;
  terminate builder
    (if ret = Types.TVoid then Sil.Return None else Sil.Unreachable);
  {
    Sil.fname = name;
    params = sil_parameters;
    ret;
    blocks = builder.blocks;
    val_ty = value_types;
  }

(* --- the entry point: a checked program -> a SIL module --- *)
let lower (program : Ast.program) : Sil.modul =
  let type_of_name n = Option.value (Types.of_name n) ~default:Types.TInt in
  let return_type_of function_decl =
    match function_decl.Ast.ret with
    | None -> Types.TVoid
    | Some n -> type_of_name n
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
      | Ast.IStmt _ -> ())
    program.Ast.items;
  let function_definitions =
    List.filter_map
      (function
        | Ast.IFunc function_decl ->
            let params =
              List.map
                (fun (parameter : Ast.param) ->
                  (parameter.Ast.pname, type_of_name parameter.Ast.ptype))
                function_decl.Ast.params
            in
            Some
              (lower_func functions function_decl.Ast.fname params
                 (return_type_of function_decl)
                 function_decl.Ast.body)
        | Ast.IStmt _ -> None)
      program.Ast.items
  in
  let main_statements =
    List.filter_map
      (function Ast.IStmt s -> Some s | Ast.IFunc _ -> None)
      program.Ast.items
  in
  let main = lower_func functions "main" [] Types.TVoid main_statements in
  { Sil.funcs = function_definitions @ [ main ] }
