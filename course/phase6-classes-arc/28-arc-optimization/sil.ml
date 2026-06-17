(* SIL (given) — concept 27's contract incl. the ownership verifier. *)

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
  | Enum_payload of value * int (* read payload slot #i of an enum VALUE — concept 12 (switch binding) *)
  (* protocols — concept 21. The existential = { payload buffer, witness-table ptr }. *)
  | Init_existential of value * string * string (* wrap a STRUCT value: (payload, struct, proto) *)
  | Apply_witness of value * int * value list
    (* dynamic dispatch: (existential, requirement SLOT, args). Loads the function pointer at
       <slot> in the existential's witness table and calls it with the payload as `self`.
       (= swiftc's `witness_method` + `apply` pair, fused for v0.) *)
  (* OWNERSHIP SSA — concept 27 (recasting concept 26's raw retain/release as STRUCTURED
     operations the verifier can check). Every class-typed value has an ownership kind:
       OWNED      — carries +1; must be CONSUMED exactly once (alloc_ref, copy_value,
                    load [take], class-typed call results)
       GUARANTEED — borrowed, +0; must NEVER be consumed (plain loads, parameters)
     Consumers: destroy_value, store, return. *)
  | Copy_value of value (* a NEW owned value (+1) of the same object — lowers to a retain *)
  | Destroy_value of value (* CONSUME an owned value (-1; at zero: deinit chains + free) *)
  | Load_take of value
    (* move the value OUT of a slot, transferring the slot's +1 to the result — ownership
       moves for free (no refcount op). swiftc: `load [take]`. Used where storage dies:
       scope exits, overwrite-the-old, the destructor's field releases. *)
  (* classes — concept 25 *)
  | Alloc_ref of string (* heap-allocate an instance of the named class; result = the reference *)
  | Ref_element_addr of value * int (* address of stored property #i of an object REFERENCE *)
  | Apply_class of value * int * value list
    (* dynamic dispatch through the VTABLE: (object, slot, args). Loads the function pointer at
       <slot> in the object's vtable and calls it with the reference as `self`.
       (= swiftc's `class_method` + `apply`, fused like Apply_witness.) *)
  | Upcast of value * string (* retype a reference to the named SUPERclass (layout is a prefix) *)
  | Same_witness of value * string
    (* concept 23: does this existential hold exactly the named concrete type? Compares the
       carried witness-table pointer against the (type, protocol) table — TYPE IDENTITY via
       TABLE IDENTITY (swiftc compares type metadata). Yields Bool; powers `as?`/`as!`. *)
  | Open_existential of value * string
    (* concept 22: extract the PAYLOAD of an existential as the named concrete struct. Emitted
       only where the type is statically known (a generic call's result whose T was inferred) —
       there is no runtime check. (= swiftc's open_existential + unchecked take.) *)

(* Terminators carry the argument values passed to their target blocks (concept 16's SSA form:
   basic-block arguments). Raw SIL (out of SILGen) passes no arguments — they are empty lists
   until mem2reg adds block arguments at join points. *)
type term =
  | Br of int * value list (* branch to block #n, passing these arguments *)
  | Cond_br of value * (int * value list) * (int * value list) (* cond, (then, args), (else, args) *)
  | Return of value option (* return a value, or Void *)
  | Unreachable (* a not-yet-filled terminator — the verifier rejects these *)
  | Trap of string (* SIGTRAP with a message — concept 13 (force-unwrap of nil; exit 133) *)
  | Abort of string (* SIGABRT with a message — concept 23 (failed `as!`; exit 134, like swiftc) *)

type block = {
  bid : int;
  mutable args : (value * Types.ty) list; (* block ARGUMENTS — the SSA "phi" (concept 16) *)
  mutable instrs : (value * instr) list; (* (result value, instruction), in program order *)
  mutable term : term;
}

type func = {
  fname : string;
  mutable params : (value * Types.ty) list;
  mutable ret : Types.ty;
  generic : bool;
    (* concept 24: lowered from `func g<T: P>` — its TProto params/values are ERASED type
       parameters, which the specializer may clone per concrete type. (A plain function taking
       `any P` is NOT generic: its existentials are real, and cloning it isn't Swift's
       semantics.) *)
  mutable blocks : block list; (* block 0 is the entry *)
  val_ty : (value, Types.ty) Hashtbl.t; (* the type of every value (filled by SILGen) *)
}

type modul = {
  funcs : func list;
  structs : Types.struct_layout list; (* concept 10 *)
  enums : Types.enum_layout list; (* concept 11 *)
  protos : Types.proto_layout list; (* concept 21 *)
  classes : Types.class_layout list; (* concept 25; cl_impls is the vtable's function names *)
  wtables : (string * string * string list) list;
      (* concept 21: one WITNESS TABLE per conformance — (proto, struct, impl function names
         in requirement order). IRGen emits each as a global array of function pointers. *)
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
  | Enum_payload (a, i) -> Printf.sprintf "%s = enum_payload %%%d, #%d %s" r a i (ty ())
  | Init_existential (p, sn, pn) ->
      Printf.sprintf "%s = init_existential %%%d : $%s, $any %s" r p sn pn
  | Apply_witness (ex, slot, args) ->
      Printf.sprintf "%s = witness_method %%%d, #%d ; apply(%s) %s" r ex slot
        (String.concat ", " (List.map (Printf.sprintf "%%%d") args))
        (ty ())
  | Open_existential (ex, sn) -> Printf.sprintf "%s = open_existential %%%d : $%s" r ex sn
  | Same_witness (ex, sn) -> Printf.sprintf "%s = same_witness %%%d, $%s" r ex sn
  | Alloc_ref cn -> Printf.sprintf "%s = alloc_ref $%s" r cn
  | Copy_value o -> Printf.sprintf "%s = copy_value %%%d" r o
  | Destroy_value o -> Printf.sprintf "destroy_value %%%d" o
  | Load_take a -> Printf.sprintf "%s = load [take] %%%d %s" r a (ty ())
  | Ref_element_addr (o, i) -> Printf.sprintf "%s = ref_element_addr %%%d, #%d" r o i
  | Apply_class (o, slot, args) ->
      Printf.sprintf "%s = class_method %%%d, #%d ; apply(%s) %s" r o slot
        (String.concat ", " (List.map (Printf.sprintf "%%%d") args))
        (ty ())
  | Upcast (o, cn) -> Printf.sprintf "%s = upcast %%%d : $%s" r o cn

let args_str args = if args = [] then "" else "(" ^ String.concat ", " (List.map (Printf.sprintf "%%%d") args) ^ ")"

let string_of_term : term -> string = function
  | Br (n, args) -> Printf.sprintf "br bb%d%s" n (args_str args)
  | Cond_br (c, (t, ta), (e, ea)) ->
      Printf.sprintf "cond_br %%%d, bb%d%s, bb%d%s" c t (args_str ta) e (args_str ea)
  | Return None -> "return"
  | Return (Some v) -> Printf.sprintf "return %%%d" v
  | Unreachable -> "unreachable" (* a genuinely-unreachable block (e.g. after both if-branches return) *)
  | Trap msg -> Printf.sprintf "trap %S" msg
  | Abort msg -> Printf.sprintf "abort %S" msg

let string_of_block (f : func) (b : block) : string =
  let hdr =
    if b.args = [] then Printf.sprintf "bb%d:" b.bid
    else
      Printf.sprintf "bb%d(%s):" b.bid
        (String.concat ", " (List.map (fun (v, t) -> Printf.sprintf "%%%d : %s" v (tystr t)) b.args))
  in
  let body = List.map (fun i -> "  " ^ string_of_instr f i) (List.rev b.instrs) in
  let lines = (hdr :: body) @ [ "  " ^ string_of_term b.term ] in
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

let string_of_proto (pl : Types.proto_layout) : string =
  let req (n, ps, r) =
    Printf.sprintf "func %s(%s) -> %s" n
      (String.concat ", " (List.map Types.string_of_ty ps))
      (Types.string_of_ty r)
  in
  Printf.sprintf "protocol %s { %s }" pl.Types.pl_name (String.concat "; " (List.map req pl.Types.pl_reqs))

let string_of_wtable ((proto, sname, fns) : string * string * string list) : string =
  Printf.sprintf "sil_witness_table %s: %s {\n%s\n}" sname proto
    (String.concat "\n" (List.mapi (fun i fn -> Printf.sprintf "  #%d: @%s" i fn) fns))

let string_of_class (cl : Types.class_layout) : string =
  let fld (n, t) = Printf.sprintf "%s: %s" n (Types.string_of_ty t) in
  let sup = match cl.Types.cl_super with Some s -> " : " ^ s | None -> "" in
  Printf.sprintf "class %s%s { %s }\n\nsil_vtable %s {\n%s\n}" cl.Types.cl_name sup
    (String.concat "; " (List.map fld cl.Types.cl_fields))
    cl.Types.cl_name
    (String.concat "\n" (List.mapi (fun i fn -> Printf.sprintf "  #%d: @%s" i fn) cl.Types.cl_impls))

let string_of_module (m : modul) : string =
  String.concat "\n\n"
    (List.map string_of_proto m.protos @ List.map string_of_struct m.structs
    @ List.map string_of_enum m.enums @ List.map string_of_class m.classes
    @ List.map string_of_wtable m.wtables @ List.map string_of_func m.funcs)

(* ---- THE OWNERSHIP VERIFIER (concept 27) ----------------------------------------------
   Statically checks the ARC discipline, turning lifetime bugs into compile errors:
     R1  an OWNED value is consumed EXACTLY ONCE (0 = a leak; 2+ = a double-destroy)
     R2  a GUARANTEED value is NEVER consumed (destroying a borrow corrupts the count —
         a copy_value must mint an owned value first)
     R3  no use of an owned value AFTER its consuming use (use-after-free, same block)
   v0 scope (documented): exactly-once is checked function-wide (our SILGen emits exactly one
   consumer per owned value; path-sensitive "once per path" is the real verifier's job), and
   use-after-consume is checked within a block. Mirrors swift/SIL/Verifier/SILOwnershipVerifier. *)

let is_class_value (f : func) (v : value) : bool =
  match Hashtbl.find_opt f.val_ty v with Some (Types.TClass _) -> true | _ -> false

(* the values an instruction CONSUMES (takes the +1 of) — class-typed operands only *)
let consumed_operands (f : func) (i : instr) : value list =
  match i with
  | Destroy_value v -> [ v ]
  | Store (v, _) when is_class_value f v -> [ v ]
  | _ -> []

let consumed_by_term (f : func) (t : term) : value list =
  match t with Return (Some v) when is_class_value f v -> [ v ] | _ -> []

(* the ownership kind of a class-typed value's DEFINITION: true = owned, false = guaranteed *)
let def_is_owned (i : instr) : bool =
  match i with
  | Alloc_ref _ | Copy_value _ | Load_take _ -> true
  | Apply _ | Apply_class _ | Apply_witness _ -> true (* class results come back +1 *)
  | _ -> false (* plain Load, Upcast of a borrow, … : guaranteed *)

let verify_ownership (m : modul) : string list =
  let errs = ref [] in
  let add s = errs := s :: !errs in
  List.iter
    (fun (f : func) ->
      (* classify every class-typed value *)
      let owned = Hashtbl.create 16 and guaranteed = Hashtbl.create 16 in
      List.iter (fun (v, _) -> if is_class_value f v then Hashtbl.replace guaranteed v ()) f.params;
      List.iter
        (fun (b : block) ->
          List.iter
            (fun (v, i) ->
              if is_class_value f v then
                if def_is_owned i then Hashtbl.replace owned v () else Hashtbl.replace guaranteed v ())
            b.instrs)
        f.blocks;
      (* count consuming uses; flag consumed guarantees *)
      let consumes : (value, int) Hashtbl.t = Hashtbl.create 16 in
      let consume v =
        if Hashtbl.mem guaranteed v then
          add (Printf.sprintf "@%s: guaranteed value %%%d consumed without a copy_value" f.fname v)
        else Hashtbl.replace consumes v (1 + Option.value (Hashtbl.find_opt consumes v) ~default:0)
      in
      List.iter
        (fun (b : block) ->
          (* R3: inside a block, an owned value must not be used after its consuming use *)
          let consumed_at : (value, int) Hashtbl.t = Hashtbl.create 8 in
          List.iteri
            (fun idx (_, i) ->
              List.iter
                (fun u ->
                  match Hashtbl.find_opt consumed_at u with
                  | Some j when j < idx ->
                      add (Printf.sprintf "@%s bb%d: owned value %%%d used after being consumed" f.fname b.bid u)
                  | _ -> ())
                (match i with
                | Copy_value v | Destroy_value v -> [ v ]
                | Store (v, a) -> [ v; a ]
                | Apply (g, args) -> g :: args
                | Apply_class (o, _, args) -> o :: args
                | Print v -> [ v ]
                | Ref_element_addr (o, _) -> [ o ]
                | Upcast (o, _) -> [ o ]
                | _ -> []);
              List.iter
                (fun v -> if Hashtbl.mem owned v then Hashtbl.replace consumed_at v idx)
                (consumed_operands f i))
            (List.rev b.instrs);
          List.iter consume (List.concat_map (fun (_, i) -> consumed_operands f i) (List.rev b.instrs));
          List.iter consume (consumed_by_term f b.term))
        f.blocks;
      (* R1: exactly once *)
      Hashtbl.iter
        (fun v () ->
          match Option.value (Hashtbl.find_opt consumes v) ~default:0 with
          | 0 -> add (Printf.sprintf "@%s: owned value %%%d is leaked (never consumed)" f.fname v)
          | 1 -> ()
          | n -> add (Printf.sprintf "@%s: owned value %%%d consumed %d times" f.fname v n))
        owned)
    m.funcs;
  List.rev !errs

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
          | Br (n, _) when not (exists n) ->
              add (Printf.sprintf "@%s bb%d: branch to nonexistent bb%d" f.fname b.bid n)
          | Cond_br (_, (t, _), (e, _)) when (not (exists t)) || not (exists e) ->
              add (Printf.sprintf "@%s bb%d: cond_br to a nonexistent block" f.fname b.bid)
          | _ -> ())
        f.blocks)
    m.funcs;
  (* concept 25: every vtable entry must name a real function *)
  List.iter
    (fun (cl : Types.class_layout) ->
      List.iter
        (fun fn ->
          if not (List.exists (fun (f : func) -> f.fname = fn) m.funcs) then
            add (Printf.sprintf "vtable %s references missing function @%s" cl.Types.cl_name fn))
        cl.Types.cl_impls)
    m.classes;
  (* concept 21: every witness-table entry must name a real function (the table outlives any
     one call site, so a dangling entry = a crash at dispatch time) *)
  List.iter
    (fun (proto, sname, fns) ->
      List.iter
        (fun fn ->
          if not (List.exists (fun (f : func) -> f.fname = fn) m.funcs) then
            add (Printf.sprintf "witness table %s: %s references missing function @%s" sname proto fn))
        fns)
    m.wtables;
  List.rev !errs
