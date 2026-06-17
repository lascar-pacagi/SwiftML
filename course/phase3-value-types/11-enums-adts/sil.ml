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

type value = int (* the result of an instruction: %0, %1, … (numbered per function) *)

type instr =
  | Int_lit of int
  | Float_lit of float
  | Bool_lit of bool
  | String_lit of string
  | Alloc_stack of string (* a stack slot for a named variable; the result is its address *)
  | Load of value (* read the value in an address *)
  | Store of value * value (* store <value> to <address> *)
  | Binop of Ast.binop * value * value
  | Unop of Ast.unop * value
  | Func_ref of string (* a reference to a SIL function *)
  | Apply of value * value list (* call a function_ref with arguments *)
  | Print of value (* the print(_:) builtin *)
  (* structs — concept 10 *)
  | Struct of value list (* build a struct value from its field values, in order *)
  | Struct_extract of value * int (* read field #i out of a struct VALUE *)
  | Struct_element_addr of value * int (* address of field #i of a struct ADDRESS (for stores) *)
  (* enums — concept 11 (a tagged union: a case index `tag` + the payload values) *)
  | Enum of int * value list (* build an enum value: case tag + payload values *)
  | Enum_tag of value (* read the case tag (an Int) out of an enum VALUE *)

type term =
  | Br of int (* unconditional branch to block #n *)
  | Cond_br of value * int * int (* branch on a Bool: (cond, then-block, else-block) *)
  | Return of value option (* return a value, or Void *)
  | Unreachable (* a not-yet-filled terminator — the verifier rejects these *)

type block = {
  bid : int;
  mutable instrs : (value * instr) list; (* (result value, instruction), in program order *)
  mutable term : term;
}

type func = {
  fname : string;
  params : (value * Types.ty) list;
  ret : Types.ty;
  mutable blocks : block list; (* block 0 is the entry *)
  val_ty : (value, Types.ty) Hashtbl.t; (* the type of every value (filled by SILGen) *)
}

type modul = {
  funcs : func list;
  structs : Types.struct_layout list; (* concept 10 *)
  enums : Types.enum_layout list; (* concept 11 *)
}

(* ---- printer: `swiftml2 --emit-sil` ------------------------------------------------- *)

let tystr t = "$" ^ Types.string_of_ty t

let string_of_instr (f : func) ((v, i) : value * instr) : string =
  let r = Printf.sprintf "%%%d" v in
  let ty () = try tystr (Hashtbl.find f.val_ty v) with Not_found -> "$?" in
  match i with
  | Int_lit n -> Printf.sprintf "%s = integer_literal $Int, %d" r n
  | Float_lit x -> Printf.sprintf "%s = float_literal $Double, %g" r x
  | Bool_lit b -> Printf.sprintf "%s = integer_literal $Bool, %b" r b
  | String_lit s -> Printf.sprintf "%s = string_literal $String, %S" r s
  | Alloc_stack name -> Printf.sprintf "%s = alloc_stack %s  // %s" r (ty ()) name
  | Load a -> Printf.sprintf "%s = load %%%d %s" r a (ty ())
  | Store (x, a) -> Printf.sprintf "store %%%d to %%%d" x a
  | Binop (op, a, b) ->
      Printf.sprintf "%s = binop \"%s\" %%%d, %%%d %s" r (Ast.string_of_binop op) a b (ty ())
  | Unop (op, a) -> Printf.sprintf "%s = unop \"%s\" %%%d %s" r (Ast.string_of_unop op) a (ty ())
  | Func_ref name -> Printf.sprintf "%s = function_ref @%s" r name
  | Apply (g, args) ->
      Printf.sprintf "%s = apply %%%d(%s)" r g
        (String.concat ", " (List.map (Printf.sprintf "%%%d") args))
  | Print a -> Printf.sprintf "%s = apply @print(%%%d)" r a
  | Struct fields ->
      Printf.sprintf "%s = struct (%s) %s" r
        (String.concat ", " (List.map (Printf.sprintf "%%%d") fields))
        (ty ())
  | Struct_extract (a, i) -> Printf.sprintf "%s = struct_extract %%%d, #%d %s" r a i (ty ())
  | Struct_element_addr (a, i) -> Printf.sprintf "%s = struct_element_addr %%%d, #%d" r a i
  | Enum (tag, payload) ->
      Printf.sprintf "%s = enum #%d (%s) %s" r tag
        (String.concat ", " (List.map (Printf.sprintf "%%%d") payload))
        (ty ())
  | Enum_tag a -> Printf.sprintf "%s = enum_tag %%%d" r a

let string_of_term : term -> string = function
  | Br n -> Printf.sprintf "br bb%d" n
  | Cond_br (c, t, e) -> Printf.sprintf "cond_br %%%d, bb%d, bb%d" c t e
  | Return None -> "return"
  | Return (Some v) -> Printf.sprintf "return %%%d" v
  | Unreachable -> "unreachable" (* a genuinely-unreachable block (e.g. after both if-branches return) *)

let string_of_block (f : func) (b : block) : string =
  let body = List.map (fun i -> "  " ^ string_of_instr f i) (List.rev b.instrs) in
  let lines = (Printf.sprintf "bb%d:" b.bid :: body) @ [ "  " ^ string_of_term b.term ] in
  String.concat "\n" lines

let string_of_func (f : func) : string =
  let ps = List.map (fun (v, t) -> Printf.sprintf "%%%d : %s" v (tystr t)) f.params in
  let header = Printf.sprintf "sil @%s(%s) -> %s {" f.fname (String.concat ", " ps) (tystr f.ret) in
  let blocks = List.map (string_of_block f) (List.rev f.blocks) in
  String.concat "\n" ((header :: blocks) @ [ "}" ])

let string_of_struct (sl : Types.struct_layout) : string =
  let fld (n, t) = Printf.sprintf "%s: %s" n (Types.string_of_ty t) in
  Printf.sprintf "struct %s { %s }" sl.Types.sl_name (String.concat "; " (List.map fld sl.Types.sl_fields))

let string_of_enum (el : Types.enum_layout) : string =
  let cs (n, tys) =
    if tys = [] then n
    else Printf.sprintf "%s(%s)" n (String.concat ", " (List.map Types.string_of_ty tys))
  in
  Printf.sprintf "enum %s { %s }" el.Types.el_name (String.concat "; " (List.map cs el.Types.el_cases))

let string_of_module (m : modul) : string =
  String.concat "\n\n"
    (List.map string_of_struct m.structs @ List.map string_of_enum m.enums @ List.map string_of_func m.funcs)

(* ---- a small verifier: every block has a real terminator and valid branch targets ---- *)

let verify (m : modul) : string list =
  let errs = ref [] in
  let add s = errs := s :: !errs in
  List.iter
    (fun (f : func) ->
      let ids = List.map (fun b -> b.bid) f.blocks in
      let exists n = List.mem n ids in
      if f.blocks = [] then add (Printf.sprintf "function '%s' has no blocks" f.fname);
      List.iter
        (fun b ->
          match b.term with
          | Br n when not (exists n) ->
              add (Printf.sprintf "@%s bb%d: branch to nonexistent bb%d" f.fname b.bid n)
          | Cond_br (_, t, e) when (not (exists t)) || not (exists e) ->
              add (Printf.sprintf "@%s bb%d: cond_br to a nonexistent block" f.fname b.bid)
          | _ -> ())
        f.blocks)
    m.funcs;
  List.rev !errs
