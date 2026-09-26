(* SIL — our Swift Intermediate Language — a *contract* (the IR types, the printer for
   `--emit-sil`, and a verifier are given; you build SILGen in silgen.ml to produce it).

   This is **raw, memory-based SIL**, exactly the shape swiftc's SILGen emits before
   optimization: every variable lives in an `alloc_stack` slot and is touched only through
   `load`/`store`; there is no SSA yet (Phase-4's mem2reg promotes these slots to SSA
   values — that's where you'll learn SSA). A function is a list of **basic blocks**; each
   block is straight-line instructions ending in a **terminator** (`br`/`cond_br`/`return`)
   — the control-flow graph that the AST's `if`/`while`/`for` finally become.

   Recognizable-but-simplified vs real swiftc SIL (we drop $*T address types, @convention,
   and name mangling). Design oracle: swift/docs/SIL.rst, swift/lib/SIL/.

   WITH §6 EXERCISES 2 AND 3 APPLIED: `of_string`, a reader for the printer's own syntax (EX2),
   and `split_critical_edges` (EX3) — both at the end of the file. *)

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

(* ---- EX2: a reader for the printer's own syntax ------------------------------------- *)
(* The inverse of string_of_module, line by line: the printer puts one instruction, one
   terminator or one block label on each line, so no tokenizer is needed — each line's shape
   is decided by its first words. Only alloc_stack, load, binop and unop print their result
   type, so those are the types the reader records; the rest print none and need none to be
   printed again. Blocks and instructions are stored newest-first, as SILGen stores them —
   the printer reverses both. *)

exception Parse_error of string

let type_of_sil (text : string) : Types.ty =
  (* `$()` is what Void PRINTS as; of_name reads what source WRITES, so it cannot read it *)
  let name = String.sub text 1 (String.length text - 1) in
  if name = "()" then Types.TVoid
  else
    match Types.of_name name with
    | Some t -> t
    | None -> raise (Parse_error ("unknown SIL type " ^ text))

let binop_of_string (text : string) : Ast.binop =
  match
    List.find_opt
      (fun op -> Ast.string_of_binop op = text)
      Ast.[ Add; Sub; Mul; Div; Mod; Eq; Ne; Lt; Le; Gt; Ge; And; Or ]
  with
  | Some op -> op
  | None -> raise (Parse_error ("unknown operator " ^ text))

let value_list (text : string) : value list =
  if String.trim text = "" then []
  else List.map (fun v -> Scanf.sscanf (String.trim v) "%%%d" Fun.id)
      (String.split_on_char ',' text)

let parse_instr (line : string) : value * instr * Types.ty option =
  let try_ fmt k = try Some (Scanf.sscanf line fmt k) with _ -> None in
  let first l = List.find_map Fun.id l in
  match
    first
      [ try_ "%%%d = integer_literal $Int, %d%!" (fun v n -> (v, Int_lit n, Some Types.TInt));
        try_ "%%%d = integer_literal $Bool, %B%!" (fun v b -> (v, Bool_lit b, Some Types.TBool));
        try_ "%%%d = float_literal $Double, %f%!" (fun v f -> (v, Float_lit f, Some Types.TDouble));
        try_ "%%%d = string_literal $String, %S%!" (fun v s -> (v, String_lit s, Some Types.TString));
        try_ "%%%d = alloc_stack %s // %s%!" (fun v t n -> (v, Alloc_stack n, Some (type_of_sil t)));
        try_ "%%%d = load %%%d %s%!" (fun v a t -> (v, Load a, Some (type_of_sil t)));
        try_ "store %%%d to %%%d%!" (fun s a -> (-1, Store (s, a), None));
        try_ "%%%d = binop %S %%%d, %%%d %s%!" (fun v o l r t ->
            (v, Binop (binop_of_string o, l, r), Some (type_of_sil t)));
        try_ "%%%d = unop \"-\" %%%d %s%!" (fun v x t -> (v, Unop (Ast.Neg, x), Some (type_of_sil t)));
        try_ "%%%d = function_ref @%s%!" (fun v n -> (v, Func_ref n, None));
        try_ "%%%d = apply @print(%%%d)%!" (fun v x -> (v, Print x, None));
        try_ "%%%d = apply %%%d(%[^)])%!" (fun v c args -> (v, Apply (c, value_list args), None));
      ]
  with
  | Some r -> r
  | None -> raise (Parse_error ("cannot read instruction: " ^ line))

let parse_term (line : string) : term option =
  let try_ fmt k = try Some (Scanf.sscanf line fmt k) with _ -> None in
  List.find_map Fun.id
    [ try_ "br bb%d%!" (fun b -> Br b);
      try_ "cond_br %%%d, bb%d, bb%d%!" (fun c t e -> Cond_br (c, t, e));
      try_ "return %%%d%!" (fun v -> Return (Some v));
      (if line = "return" then Some (Return None) else None);
      (if line = "unreachable" then Some Unreachable else None) ]

let parse_header (line : string) : func =
  Scanf.sscanf line "sil @%[^(](%[^)]) -> %s {%!" (fun name params ret ->
      let params =
        if String.trim params = "" then []
        else
          List.map
            (fun p -> Scanf.sscanf (String.trim p) "%%%d : %s" (fun v t -> (v, type_of_sil t)))
            (String.split_on_char ',' params)
      in
      let val_ty = Hashtbl.create 16 in
      List.iter (fun (v, t) -> Hashtbl.replace val_ty v t) params;
      { fname = name; params; ret = type_of_sil ret; blocks = []; val_ty })

let of_string (text : string) : modul =
  let funcs = ref [] and current = ref None and block = ref None in
  (* a `store` has no result, but SILGen numbers it anyway — the gap between %1 and %3. The
     number is never printed and nothing refers to it, so the reader draws it from a counter
     far above any real value rather than guess it: blocks do not print in the order their
     values were made, so "one more than the line before" could collide with a real one *)
  let unprinted = ref 1_000_000 in
  List.iter
    (fun raw ->
      let line = String.trim raw in
      if line = "" then ()
      else if String.length line > 4 && String.sub line 0 4 = "sil " then (
        current := Some (parse_header line);
        block := None)
      else if line = "}" then (
        match !current with
        | Some f ->
            funcs := f :: !funcs;
            current := None
        | None -> raise (Parse_error "`}` outside a function"))
      else
        match (!current, Scanf.sscanf_opt line "bb%d:%!" Fun.id) with
        | Some f, Some bid ->
            let b = { bid; instrs = []; term = Unreachable } in
            f.blocks <- b :: f.blocks;
            block := Some b
        | Some f, None -> (
            let b =
              match !block with Some b -> b | None -> raise (Parse_error "instruction outside a block")
            in
            match parse_term line with
            | Some t -> b.term <- t
            | None ->
                let v, instr, ty = parse_instr line in
                let v = if v < 0 then (incr unprinted; !unprinted) else v in
                Option.iter (Hashtbl.replace f.val_ty v) ty;
                b.instrs <- (v, instr) :: b.instrs)
        | None, _ -> raise (Parse_error ("text outside a function: " ^ line)))
    (String.split_on_char '\n' text);
  { funcs = List.rev !funcs }

(* ---- EX3: split every critical edge ------------------------------------------------ *)
(* An edge u -> v is CRITICAL when u has two successors and v two predecessors: code meant to
   run only on that edge has nowhere to go — at the end of u it would run on u's other edge
   too, at the start of v on v's other entry too. Splitting inserts an empty block w on the
   edge, u -> w -> v, and w is the place. The only terminator with two successors here is
   cond_br, and a cond_br whose two edges go to the same block has two edges into it. *)

let successors : term -> int list = function
  | Br b -> [ b ]
  | Cond_br (_, t, e) -> [ t; e ]
  | Return _ | Unreachable -> []

let split_func (f : func) : unit =
  let preds = Hashtbl.create 16 in
  List.iter
    (fun b -> List.iter (fun s -> Hashtbl.replace preds s (1 + Option.value ~default:0 (Hashtbl.find_opt preds s)))
        (successors b.term))
    f.blocks;
  let next = ref (1 + List.fold_left (fun m b -> max m b.bid) 0 f.blocks) in
  let split target =
    if Option.value ~default:0 (Hashtbl.find_opt preds target) < 2 then target
    else (
      let w = { bid = !next; instrs = []; term = Br target } in
      incr next;
      f.blocks <- w :: f.blocks;
      w.bid)
  in
  List.iter
    (fun b ->
      match b.term with
      | Cond_br (c, t, e) -> b.term <- Cond_br (c, split t, split e)
      | _ -> ())
    (List.filter (fun b -> match b.term with Cond_br _ -> true | _ -> false) f.blocks)

let split_critical_edges (m : modul) : modul =
  List.iter split_func m.funcs;
  m
