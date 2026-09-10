(* SIL — our Swift Intermediate Language — a *contract* (the IR types, the printer for
   `--emit-sil`, and a verifier are given; you build SILGen in silgen.ml to produce it).

   This is **raw, memory-based SIL**, exactly the shape swiftc's SILGen emits before
   optimization: every variable lives in an `alloc_stack` slot and is touched only through
   `load`/`store`; there is no SSA yet (Phase-4's mem2reg promotes these slots to SSA
   values — that's where you'll learn SSA). A function is a list of **basic blocks**; each
   block is straight-line instructions ending in a **terminator** (`br`/`cond_br`/`return`)
   — the control-flow graph that the AST's `if`/`while`/`for` finally become.

   Recognizable-but-simplified vs real swiftc SIL (we drop $*T address types, @convention,
   and name mangling). Design oracle: swift/docs/SIL.rst, swift/lib/SIL/. *)

type value =
  int (* the result of an instruction: %0, %1, … (numbered per function) *)

type instr =
  | Int_lit of int
  | Float_lit of float
  | Bool_lit of bool
  | String_lit of string
  | Alloc_stack of
      string (* a stack slot for a named variable; the result is its address *)
  | Load of value (* read the value in an address *)
  | Store of value * value (* store <value> to <address> *)
  | Binop of Ast.binop * value * value
  | Unop of Ast.unop * value
  | Func_ref of string (* a reference to a SIL function *)
  | Apply of value * value list (* call a function_ref with arguments *)
  | Print of value (* the print(_:) builtin *)

type term =
  | Br of int (* unconditional branch to block #n *)
  | Cond_br of
      value * int * int (* branch on a Bool: (cond, then-block, else-block) *)
  | Return of value option (* return a value, or Void *)
  | Unreachable
(* control never continues from here; also a block's term until one is set *)

type block = {
  bid : int;
  mutable instrs : (value * instr) list;
      (* (result value, instruction), in program order *)
  mutable term : term;
}

type func = {
  fname : string;
  params : (value * Types.ty) list;
  ret : Types.ty;
  mutable blocks : block list; (* block 0 is the entry *)
  val_ty : (value, Types.ty) Hashtbl.t;
      (* the type of every value (filled by SILGen) *)
}

type modul = { funcs : func list }

(* ---- printer: `swiftml2 --emit-sil` ------------------------------------------------- *)

let sil_type type_ = "$" ^ Types.string_of_ty type_

let string_of_instr (function_definition : func)
    ((value, instruction) : value * instr) : string =
  let result_name = Printf.sprintf "%%%d" value in
  let result_type () =
    try sil_type (Hashtbl.find function_definition.val_ty value)
    with Not_found -> "$?"
  in
  match instruction with
  | Int_lit integer ->
      Printf.sprintf "%s = integer_literal $Int, %d" result_name integer
  | Float_lit number ->
      Printf.sprintf "%s = float_literal $Double, %g" result_name number
  | Bool_lit boolean ->
      Printf.sprintf "%s = integer_literal $Bool, %b" result_name boolean
  | String_lit text ->
      Printf.sprintf "%s = string_literal $String, %S" result_name text
  | Alloc_stack name ->
      Printf.sprintf "%s = alloc_stack %s  // %s" result_name (result_type ())
        name
  | Load address ->
      Printf.sprintf "%s = load %%%d %s" result_name address (result_type ())
  | Store (stored_value, address) ->
      Printf.sprintf "store %%%d to %%%d" stored_value address
  | Binop (operator, left, right) ->
      Printf.sprintf "%s = binop \"%s\" %%%d, %%%d %s" result_name
        (Ast.string_of_binop operator)
        left right (result_type ())
  | Unop (operator, operand) ->
      Printf.sprintf "%s = unop \"%s\" %%%d %s" result_name
        (Ast.string_of_unop operator)
        operand (result_type ())
  | Func_ref name -> Printf.sprintf "%s = function_ref @%s" result_name name
  | Apply (callee, arguments) ->
      Printf.sprintf "%s = apply %%%d(%s)" result_name callee
        (String.concat ", " (List.map (Printf.sprintf "%%%d") arguments))
  | Print operand ->
      Printf.sprintf "%s = apply @print(%%%d)" result_name operand

let string_of_term : term -> string = function
  | Br target -> Printf.sprintf "br bb%d" target
  | Cond_br (condition, then_target, else_target) ->
      Printf.sprintf "cond_br %%%d, bb%d, bb%d" condition then_target
        else_target
  | Return None -> "return"
  | Return (Some value) -> Printf.sprintf "return %%%d" value
  | Unreachable -> "unreachable"
(* a genuinely-unreachable block (e.g. after both if-branches return) *)

let string_of_block (function_definition : func) (block : block) : string =
  let instruction_lines =
    List.map
      (fun instruction ->
        "  " ^ string_of_instr function_definition instruction)
      (List.rev block.instrs)
  in
  let lines =
    (Printf.sprintf "bb%d:" block.bid :: instruction_lines)
    @ [ "  " ^ string_of_term block.term ]
  in
  String.concat "\n" lines

let string_of_func (function_definition : func) : string =
  let parameters =
    List.map
      (fun (value, parameter_type) ->
        Printf.sprintf "%%%d : %s" value (sil_type parameter_type))
      function_definition.params
  in
  let header =
    Printf.sprintf "sil @%s(%s) -> %s {" function_definition.fname
      (String.concat ", " parameters)
      (sil_type function_definition.ret)
  in
  let blocks =
    List.map
      (string_of_block function_definition)
      (List.rev function_definition.blocks)
  in
  String.concat "\n" ((header :: blocks) @ [ "}" ])

let string_of_module (sil_module : modul) : string =
  String.concat "\n\n" (List.map string_of_func sil_module.funcs)

(* ---- a small verifier: every block has a real terminator and valid branch targets ---- *)

let verify (sil_module : modul) : string list =
  let errors = ref [] in
  let report message = errors := message :: !errors in
  List.iter
    (fun (function_definition : func) ->
      let block_ids =
        List.map (fun block -> block.bid) function_definition.blocks
      in
      let block_exists block_id = List.mem block_id block_ids in
      if function_definition.blocks = [] then
        report
          (Printf.sprintf "function '%s' has no blocks"
             function_definition.fname);
      List.iter
        (fun block ->
          match block.term with
          | Br target when not (block_exists target) ->
              report
                (Printf.sprintf "@%s bb%d: branch to nonexistent bb%d"
                   function_definition.fname block.bid target)
          | Cond_br (_, then_target, else_target)
            when (not (block_exists then_target))
                 || not (block_exists else_target) ->
              report
                (Printf.sprintf "@%s bb%d: cond_br to a nonexistent block"
                   function_definition.fname block.bid)
          | _ -> ())
        function_definition.blocks)
    sil_module.funcs;
  List.rev !errors
