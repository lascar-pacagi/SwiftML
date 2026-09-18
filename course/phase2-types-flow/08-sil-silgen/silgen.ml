(* SILGen — concept 08 (skeleton). The builder API, the arithmetic/call lowering and
   lower_func/lower are given. You implement three things: the MEMORY MODEL (TODO(08a) — a
   variable is a stack slot, read with load, written with store), the ordinary BINARY OPERATOR
   (TODO(08b)), and the CONTROL-FLOW lowering (TODO(08c) in gen_statement) — the heart of SILGen:
   turning the tree into a basic-block CFG.
   Reference: solution/silgen.ml.

   Lower the TYPE-CHECKED tree (`Tast`) to raw, memory-based SIL.

   SILGen consumes what Sema produced, and that is the whole reason this file is as short as
   it is. Every node arrives carrying its type and every name arrives resolved, so there is
   nothing here that asks "what did the checker decide?" — no second type system, no registry
   lookups, no coercion logic. PLAN.md §0.1 records what this file looked like when it did
   have to ask, and the bugs that came of it.

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

let rec gen_expression (builder : builder) (expression : Tast.expr) : Sil.value =
  (* `ty` is the type Sema concluded for this node. Reading it is the whole of what used to be
     `gen_expression_as` plus a re-generation dance — see the literal arm below. *)
  let ty = expression.Tast.ty in
  match expression.Tast.e with
  (* THE COERCION, already decided. An integer literal that checked at Double carries Double, so
     it is BORN a Double here. Nothing in this file has to notice that `2` sits beside a `d`. *)
  | Tast.Int_lit n when ty = Types.TDouble ->
      emit builder (Sil.Float_lit (float_of_int n)) Types.TDouble
  | Tast.Int_lit n -> emit builder (Sil.Int_lit n) Types.TInt
  | Tast.Double_lit number -> emit builder (Sil.Float_lit number) Types.TDouble
  | Tast.Bool_lit boolean -> emit builder (Sil.Bool_lit boolean) Types.TBool
  | Tast.String_lit text -> emit builder (Sil.String_lit text) Types.TString
  (* `e as T` — the operand was already checked AT T, so the coercion has nothing left to do *)
  | Tast.Coerce operand_expression -> gen_expression builder operand_expression
  | Tast.Local name ->
      ignore name;
      (* TODO(08a): a variable READ — find its slot with `address_of` and `load` from it. The
         result's type is the slot's element type (`value_type builder addr`). §3. *)
      failwith "TODO(08a): load a variable from its slot"
  | Tast.Unary (op, operand_expression) ->
      let value = gen_expression builder operand_expression in
      emit builder (Sil.Unop (op, value)) ty
  (* SHORT-CIRCUIT `&&` / `||` (concept 06 semantics, lowered here) — NOT
     bitwise: the right operand is evaluated only on the deciding edge, so its
     side effects (a trapping `a[i]` in `i < n && a[i]`,
     a force-unwrap, a throwing call) never run on the short path. Lowered to a cond_br diamond, the
     result merged through a stack slot (mem2reg promotes it to a phi). *)
  | Tast.Binary (((Ast.And | Ast.Or) as op), left_expression, right_expression) ->
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
  | Tast.Binary (op, left_expression, right_expression) ->
      ignore (op, left_expression, right_expression);
      (* TODO(08b): the ordinary binary operator — lower both operands, then emit the `Binop`.
         Note what you do NOT have to do: both operands already carry their final type, and so
         does this node (`ty`), because Sema recorded all three. There is no coercion to spot
         and nothing to re-generate. PLAN.md §0.1 is the story of the version that had to. §3. *)
      failwith "TODO(08b): lower a binary operator"
  (* RESOLVED calls: Sema already decided whether this was print or a declared function, so
     there is no `Hashtbl.mem builder.functions` guess to get wrong. *)
  | Tast.Print argument -> emit builder (Sil.Print (gen_expression builder argument)) Types.TVoid
  | Tast.Fn_call (function_name, arguments) ->
      let argument_values = List.map (gen_expression builder) arguments in
      let function_reference = emit builder (Sil.Func_ref function_name) ty in
      emit builder (Sil.Apply (function_reference, argument_values)) ty

(* --- lowering statements; gen_block stops after a terminator (dead code) --- *)
let rec gen_block (builder : builder) (statements : Tast.stmt list) : unit =
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

and gen_statement (builder : builder) (s : Tast.stmt) : unit =
  match s with
  | Tast.Let { name; value; _ } ->
      ignore (name, value);
      (* TODO(08a): a binding — lower the value, `Alloc_stack` a slot of its type, remember the
         slot with `bind_variable`, and `Store` into it. The slot takes the VALUE's type, which
         Sema recorded: an annotated `let d: Double = 1` arrives with its literal already
         carrying Double, so there is nothing to coerce here. §3. *)
      failwith "TODO(08a): give the variable a slot and store into it"
  | Tast.Assign { name; value; _ } ->
      ignore (name, value);
      (* TODO(08a): assignment — lower the value and `Store` it into the existing slot. *)
      failwith "TODO(08a): store into the variable's slot"
  | Tast.Expr_stmt expression -> ignore (gen_expression builder expression)
  | Tast.Return (eo, _) -> (
      match eo with
      | Some expression ->
          let value = gen_expression builder expression in
          terminate builder (Sil.Return (Some value))
      | None -> terminate builder (Sil.Return None))
  | Tast.If _ ->
      ignore (new_block, switch_to, terminate, gen_block);
      (* TODO(08c): `if` — the DIAMOND. Lower the condition, make the blocks, `Cond_br` to them,
         fill each, and have both arms `Br` to the merge block. §3. *)
      failwith "TODO(08c): lower `if`"
  | Tast.While _ ->
      ignore (enter_loop, leave_loop);
      (* TODO(08c): `while` — header / body / exit, with the BACK EDGE from the body to the
         header. Register the loop so `break`/`continue` know where to go. §3. *)
      failwith "TODO(08c): lower `while`"
  | Tast.For _ ->
      (* TODO(08c): `for v in lo ..< hi` — DESUGAR to a counted while loop: a slot for `v`,
         header / body / latch / exit. `continue` must jump to the LATCH, not the header, or the
         increment is skipped and the loop never ends. §3. *)
      failwith "TODO(08c): lower `for`"
  | Tast.Break _ ->
      ignore break_target;
      (* TODO(08c): `break` — branch to the enclosing loop's exit block. *)
      failwith "TODO(08c): lower `break`"
  | Tast.Continue _ ->
      ignore continue_target;
      (* TODO(08c): `continue` — branch to the enclosing loop's continue target. *)
      failwith "TODO(08c): lower `continue`"

(* --- lowering a function: params get slots; then the body --- *)
let lower_func functions (name : string) (params : (string * Types.ty) list)
    (ret : Types.ty) (body : Tast.stmt list) : Sil.func =
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

(* --- the entry point: a type-checked program -> a SIL module ---
   Note what is NOT here: no `Types.of_name`. A `Tast.func_decl`'s parameter and return types are
   already types, not written names, so there is nothing left to resolve. *)
let lower (program : Tast.program) : Sil.modul =
  let functions = Hashtbl.create 16 in
  List.iter
    (function
      | Tast.IFunc function_decl ->
          let parameter_types =
            List.map (fun (p : Tast.param) -> p.Tast.pty) function_decl.Tast.params
          in
          Hashtbl.replace functions function_decl.Tast.fname
            (parameter_types, function_decl.Tast.ret)
      | Tast.IStmt _ -> ())
    program.Tast.items;
  let function_definitions =
    List.filter_map
      (function
        | Tast.IFunc function_decl ->
            let params =
              List.map
                (fun (p : Tast.param) -> (p.Tast.pname, p.Tast.pty))
                function_decl.Tast.params
            in
            Some
              (lower_func functions function_decl.Tast.fname params
                 function_decl.Tast.ret function_decl.Tast.body)
        | Tast.IStmt _ -> None)
      program.Tast.items
  in
  let main_statements =
    List.filter_map
      (function Tast.IStmt s -> Some s | Tast.IFunc _ -> None)
      program.Tast.items
  in
  let main = lower_func functions "main" [] Types.TVoid main_statements in
  { Sil.funcs = function_definitions @ [ main ] }
