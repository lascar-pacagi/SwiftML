(* SILGen — concept 09 (GIVEN, complete; you wrote it in concept 08): lower the TYPE-CHECKED tree (`Tast`) to raw,
   memory-based SIL.

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
      let addr = address_of builder name in
      emit builder (Sil.Load addr) (value_type builder addr)
      (* the slot's element type *)
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
      (* Both operands already carry their final type, and so does this node. Compare what this
         arm used to be: generate the left, notice the right was a Double, generate the right AT
         Double, then RE-generate the left at Double — leaving the abandoned first copy in the
         block, where at -Onone it still ran. That is PLAN.md §0.1's bug, and it is not fixed
         here so much as made impossible to write. *)
      let left_value = gen_expression builder left_expression in
      let right_value = gen_expression builder right_expression in
      emit builder (Sil.Binop (op, left_value, right_value)) ty
  (* RESOLVED calls: Sema already decided whether this was print or a declared function, so
     there is no `Hashtbl.mem builder.functions` guess to get wrong. *)
  | Tast.Print argument -> emit builder (Sil.Print (gen_expression builder argument)) Types.TVoid
  | Tast.Fn_call (function_name, chosen, arguments) ->
      (* MANGLING. Two functions may share a name in this concept, and a symbol may not — so
         the SIL name is the source name plus the index of the declaration the solver chose.
         `show$1` is the second `show`. Swift does the same thing for the same reason, with a
         real mangling scheme that encodes the whole signature (`$s4main4showyS2iF`); the
         index is enough here because the checker has already picked, and this is the first
         place in the course where a NAME is not a unique identifier. *)
      let argument_values = List.map (gen_expression builder) arguments in
      let function_reference =
        emit builder (Sil.Func_ref (Printf.sprintf "%s$%d" function_name chosen)) ty
      in
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
      (* the slot takes the value's type, which Sema recorded — an annotated `let d: Double = 1`
         arrives with the literal already carrying Double, so there is nothing to coerce *)
      let value = gen_expression builder value in
      let addr = emit builder (Sil.Alloc_stack name) (value_type builder value) in
      bind_variable builder name addr;
      emit_void builder (Sil.Store (value, addr))
  | Tast.Assign { name; value; _ } ->
      let value = gen_expression builder value in
      emit_void builder (Sil.Store (value, address_of builder name))
  | Tast.Expr_stmt expression -> ignore (gen_expression builder expression)
  | Tast.Return (eo, _) -> (
      match eo with
      | Some expression ->
          let value = gen_expression builder expression in
          terminate builder (Sil.Return (Some value))
      | None -> terminate builder (Sil.Return None))
  | Tast.If { cond; then_blk; else_blk; _ } ->
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
  | Tast.While { cond; body; _ } ->
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
  | Tast.For { var; lo; hi; body; _ } ->
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
  | Tast.Break _ -> (
      match break_target builder with
      | Some exit_target -> terminate builder (Sil.Br exit_target)
      | None -> ())
  | Tast.Continue _ -> (
      match continue_target builder with
      | Some condition_value -> terminate builder (Sil.Br condition_value)
      | None -> ())

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
(* the index of a declaration within its own overload set, in source order *)
let mangled_names (program : Tast.program) : (Token.span, string) Hashtbl.t =
  let seen = Hashtbl.create 16 and out = Hashtbl.create 16 in
  List.iter
    (function
      | Tast.IFunc f ->
          let n = Option.value ~default:0 (Hashtbl.find_opt seen f.Tast.fname) in
          Hashtbl.replace seen f.Tast.fname (n + 1);
          Hashtbl.replace out f.Tast.fspan (Printf.sprintf "%s$%d" f.Tast.fname n)
      | Tast.IStmt _ -> ())
    program.Tast.items;
  out

let lower (program : Tast.program) : Sil.modul =
  let names = mangled_names program in
  let mangled (f : Tast.func_decl) =
    Option.value ~default:f.Tast.fname (Hashtbl.find_opt names f.Tast.fspan)
  in
  let functions = Hashtbl.create 16 in
  List.iter
    (function
      | Tast.IFunc function_decl ->
          let parameter_types =
            List.map (fun (p : Tast.param) -> p.Tast.pty) function_decl.Tast.params
          in
          (* keyed by the MANGLED name, so two declarations that share a source name do not
             overwrite each other — the bug this would be without the index *)
          Hashtbl.replace functions (mangled function_decl)
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
              (lower_func functions (mangled function_decl) params
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
