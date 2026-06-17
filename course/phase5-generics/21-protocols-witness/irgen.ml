(* IRGen (given) — lower a SIL module to LLVM IR text. SIL blocks/instructions map nearly
   one-to-one onto LLVM; block arguments lower to phi nodes (concept 16). Concept 21 adds the
   PROTOCOL machinery: an existential `any P` is `{ [N x i64] payload, ptr witness_table }`;
   each conformance emits a global table of function pointers plus one THUNK per requirement
   (the thunk loads the concrete self out of the payload buffer and calls the real method);
   `apply_witness` loads the function pointer from the table and calls it. *)

let rec llty : Types.ty -> string = function
  | Types.TInt -> "i64"
  | Types.TBool -> "i1"
  | Types.TDouble -> "double"
  | Types.TString -> "ptr"
  | Types.TVoid -> "void"
  | Types.TStruct n -> "%" ^ n (* an LLVM named aggregate type — concept 10 *)
  | Types.TEnum n -> "%" ^ n (* a tagged union { i64 tag, i64×payload } — concept 11 *)
  | Types.TOptional t -> Printf.sprintf "{ i64, %s }" (llty t) (* an inline { tag, payload } — concept 13 *)
  | Types.TProto n -> "%any." ^ n (* an existential { [N x i64] payload, ptr table } — concept 21 *)

let emit_llvm (m : Sil.modul) : string =
  (* concept 21: how many 8-byte words a value of each type occupies — used to size the
     existential payload buffer. (Every field in our world fits a word.) *)
  let slay n = List.find (fun (sl : Types.struct_layout) -> sl.Types.sl_name = n) m.Sil.structs in
  let elay n = List.find (fun (el : Types.enum_layout) -> el.Types.el_name = n) m.Sil.enums in
  let rec words : Types.ty -> int = function
    | Types.TInt | Types.TBool | Types.TDouble | Types.TString -> 1
    | Types.TVoid -> 0
    | Types.TStruct n -> List.fold_left (fun a (_, t) -> a + words t) 0 (slay n).Types.sl_fields
    | Types.TEnum n -> 1 + Types.max_payload (elay n)
    | Types.TOptional t -> 1 + words t
    | Types.TProto p -> 1 + ex_words p
  (* the payload buffer of `any P` is sized to P's LARGEST conforming struct — a whole-module
     luxury swiftc doesn't have (it uses a fixed 3-word buffer and spills big values to the
     heap; that indirection is concept 23). Minimum 1 so the type is well-formed. *)
  and ex_words (pname : string) : int =
    List.fold_left
      (fun acc (pn, sn, _) -> if pn = pname then max acc (words (Types.TStruct sn)) else acc)
      1 m.Sil.wtables
  in
  let globals = Buffer.create 256 in
  let out = Buffer.create 1024 in
  let strn = ref 0 in
  let escape s =
    let b = Buffer.create (String.length s) in
    String.iter
      (fun c ->
        if c = '"' || c = '\\' || Char.code c < 32 || Char.code c > 126 then
          Buffer.add_string b (Printf.sprintf "\\%02X" (Char.code c))
        else Buffer.add_char b c)
      s;
    Buffer.contents b
  in
  let add_string_const s =
    let name = Printf.sprintf "@.str%d" !strn in
    incr strn;
    Buffer.add_string globals
      (Printf.sprintf "%s = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n" name
         (String.length s + 1) (escape s));
    name
  in
  let gen_func (f : Sil.func) =
    let is_main = f.Sil.fname = "main" in
    let opnd : (Sil.value, string) Hashtbl.t = Hashtbl.create 64 in
    let nt = ref 0 in
    let fresh () = let n = !nt in incr nt; Printf.sprintf "%%t%d" n in
    let op x = Hashtbl.find opnd x in
    let vty x = Hashtbl.find f.Sil.val_ty x in
    let p s = Buffer.add_string out s in
    (* PRE-PASS: assign a stable LLVM operand to every SIL value, so a phi can name an incoming
       value even from a not-yet-emitted (back-edge) block. Constants map to a literal/global;
       everything else (params, block args, instruction results) maps to %vN. *)
    let name v = Printf.sprintf "%%v%d" v in
    let assign (v, instr) =
      match (instr : Sil.instr) with
      | Sil.Int_lit n -> Hashtbl.replace opnd v (string_of_int n)
      | Sil.Bool_lit b -> Hashtbl.replace opnd v (if b then "1" else "0")
      | Sil.Float_lit x -> Hashtbl.replace opnd v (Printf.sprintf "0x%016LX" (Int64.bits_of_float x))
      | Sil.String_lit s -> Hashtbl.replace opnd v (add_string_const s)
      | Sil.Func_ref nm -> Hashtbl.replace opnd v ("@" ^ nm)
      | _ -> Hashtbl.replace opnd v (name v)
    in
    List.iter (fun (v, _) -> Hashtbl.replace opnd v (name v)) f.Sil.params;
    List.iter
      (fun (b : Sil.block) ->
        List.iter (fun (v, _) -> Hashtbl.replace opnd v (name v)) b.Sil.args;
        List.iter assign b.Sil.instrs)
      f.Sil.blocks;
    (* who branches into each block, and with which arguments (for phi nodes) *)
    let incoming : (int, (int * Sil.value list) list) Hashtbl.t = Hashtbl.create 16 in
    let add_inc tgt pred args =
      Hashtbl.replace incoming tgt ((pred, args) :: (try Hashtbl.find incoming tgt with Not_found -> []))
    in
    List.iter
      (fun (b : Sil.block) ->
        match b.Sil.term with
        | Sil.Br (n, args) -> add_inc n b.Sil.bid args
        | Sil.Cond_br (_, (t, ta), (e, ea)) -> add_inc t b.Sil.bid ta; add_inc e b.Sil.bid ea
        | _ -> ())
      f.Sil.blocks;
    let pdecls = List.map (fun (v, t) -> Printf.sprintf "%s %s" (llty t) (op v)) f.Sil.params in
    let ret_ll = if is_main then "i32" else llty f.Sil.ret in
    p (Printf.sprintf "define %s @%s(%s) {\n" ret_ll f.Sil.fname (String.concat ", " pdecls));
    let gen_binop v bop l r =
      let t = vty l in
      let r' = op v in
      let mn =
        match (bop, t) with
        | Ast.Add, Types.TInt -> "add i64" | Ast.Sub, Types.TInt -> "sub i64"
        | Ast.Mul, Types.TInt -> "mul i64" | Ast.Div, Types.TInt -> "sdiv i64"
        | Ast.Mod, Types.TInt -> "srem i64"
        | Ast.Add, Types.TDouble -> "fadd double" | Ast.Sub, Types.TDouble -> "fsub double"
        | Ast.Mul, Types.TDouble -> "fmul double" | Ast.Div, Types.TDouble -> "fdiv double"
        | Ast.Eq, Types.TInt -> "icmp eq i64" | Ast.Ne, Types.TInt -> "icmp ne i64"
        | Ast.Lt, Types.TInt -> "icmp slt i64" | Ast.Le, Types.TInt -> "icmp sle i64"
        | Ast.Gt, Types.TInt -> "icmp sgt i64" | Ast.Ge, Types.TInt -> "icmp sge i64"
        | Ast.Eq, Types.TDouble -> "fcmp oeq double" | Ast.Ne, Types.TDouble -> "fcmp one double"
        | Ast.Lt, Types.TDouble -> "fcmp olt double" | Ast.Le, Types.TDouble -> "fcmp ole double"
        | Ast.Gt, Types.TDouble -> "fcmp ogt double" | Ast.Ge, Types.TDouble -> "fcmp oge double"
        | (Ast.Eq | Ast.Ne), Types.TBool -> Printf.sprintf "icmp %s i1" (if bop = Ast.Eq then "eq" else "ne")
        | Ast.And, _ -> "and i1" | Ast.Or, _ -> "or i1"
        | _ -> "add i64" (* String ops not lowered in this subset *)
      in
      p (Printf.sprintf "  %s = %s %s, %s\n" r' mn (op l) (op r));
      Hashtbl.replace opnd v r'
    and gen_print x =
      match vty x with
      | Types.TInt -> p (Printf.sprintf "  call i32 (ptr, ...) @printf(ptr @.fmt_int, i64 %s)\n" (op x))
      | Types.TBool ->
          let s = fresh () in
          p (Printf.sprintf "  %s = select i1 %s, ptr @.btrue, ptr @.bfalse\n" s (op x));
          p (Printf.sprintf "  call i32 (ptr, ...) @printf(ptr @.fmt_str, ptr %s)\n" s)
      | Types.TString -> p (Printf.sprintf "  call i32 (ptr, ...) @printf(ptr @.fmt_str, ptr %s)\n" (op x))
      | Types.TDouble -> p (Printf.sprintf "  call i32 (ptr, ...) @printf(ptr @.fmt_dbl, double %s)\n" (op x))
      | Types.TVoid -> ()
    in
    let gen_instr (v, i) =
      match (i : Sil.instr) with
      (* constants/func_refs were assigned in the pre-pass; they emit no instruction *)
      | Sil.Int_lit _ | Sil.Bool_lit _ | Sil.Float_lit _ | Sil.String_lit _ | Sil.Func_ref _ -> ()
      | Sil.Alloc_stack _ -> () (* hoisted into the entry block — see gen_allocas below *)
      | Sil.Load a -> p (Printf.sprintf "  %s = load %s, ptr %s\n" (op v) (llty (vty v)) (op a))
      | Sil.Store (x, a) -> p (Printf.sprintf "  store %s %s, ptr %s\n" (llty (vty x)) (op x) (op a))
      | Sil.Binop (op0, l, r) -> gen_binop v op0 l r
      | Sil.Unop (Ast.Neg, x) ->
          if vty x = Types.TDouble then p (Printf.sprintf "  %s = fneg double %s\n" (op v) (op x))
          else p (Printf.sprintf "  %s = sub i64 0, %s\n" (op v) (op x))
      | Sil.Apply (fr, args) ->
          let argstr =
            String.concat ", " (List.map (fun a -> Printf.sprintf "%s %s" (llty (vty a)) (op a)) args)
          in
          let rt = vty v in
          if rt = Types.TVoid then p (Printf.sprintf "  call void %s(%s)\n" (op fr) argstr)
          else p (Printf.sprintf "  %s = call %s %s(%s)\n" (op v) (llty rt) (op fr) argstr)
      | Sil.Print x -> gen_print x
      (* structs — concept 10. The chain's LAST insertvalue targets the result name [op v]. *)
      | Sil.Struct fields ->
          let sty = llty (vty v) in
          let n = List.length fields in
          if n = 0 then p (Printf.sprintf "  %s = freeze %s undef\n" (op v) sty)
          else
            let acc = ref "undef" in
            List.iteri
              (fun idx fv ->
                let r = if idx = n - 1 then op v else fresh () in
                p (Printf.sprintf "  %s = insertvalue %s %s, %s %s, %d\n" r sty !acc (llty (vty fv)) (op fv) idx);
                acc := r)
              fields
      | Sil.Struct_extract (a, idx) ->
          p (Printf.sprintf "  %s = extractvalue %s %s, %d\n" (op v) (llty (vty a)) (op a) idx)
      | Sil.Struct_element_addr (a, idx) ->
          p (Printf.sprintf "  %s = getelementptr %s, ptr %s, i32 0, i32 %d\n" (op v) (llty (vty a)) (op a) idx)
      (* enums — concept 11: a tagged union { tag at #0, payload at #1.. } *)
      | Sil.Enum (tag, payload) ->
          let ety = llty (vty v) in
          let n = List.length payload in
          let r0 = if n = 0 then op v else fresh () in
          p (Printf.sprintf "  %s = insertvalue %s undef, i64 %d, 0\n" r0 ety tag);
          let acc = ref r0 in
          List.iteri
            (fun idx fv ->
              let r = if idx = n - 1 then op v else fresh () in
              p (Printf.sprintf "  %s = insertvalue %s %s, %s %s, %d\n" r ety !acc (llty (vty fv)) (op fv) (idx + 1));
              acc := r)
            payload
      | Sil.Enum_tag a -> p (Printf.sprintf "  %s = extractvalue %s %s, 0\n" (op v) (llty (vty a)) (op a))
      | Sil.Enum_payload (a, idx) ->
          p (Printf.sprintf "  %s = extractvalue %s %s, %d\n" (op v) (llty (vty a)) (op a) (idx + 1))
      (* protocols — concept 21 *)
      | Sil.Init_existential (pv, sn, pn) ->
          (* store the concrete struct into this site's payload buffer, reload it AS the buffer
             type, then pair it with the conformance's witness table *)
          let n = ex_words pn in
          let buf = Printf.sprintf "%%ex%d" v in
          let arr = fresh () and half = fresh () in
          p (Printf.sprintf "  store %%%s %s, ptr %s\n" sn (op pv) buf);
          p (Printf.sprintf "  %s = load [%d x i64], ptr %s\n" arr n buf);
          p (Printf.sprintf "  %s = insertvalue %%any.%s undef, [%d x i64] %s, 0\n" half pn n arr);
          p (Printf.sprintf "  %s = insertvalue %%any.%s %s, ptr @wt.%s.%s, 1\n" (op v) pn half pn sn)
      | Sil.Apply_witness (ex, slot, args) ->
          (* dynamic dispatch: spill the payload to this site's buffer (the callee takes `self`
             BY POINTER — it doesn't know the concrete type), load the function pointer from
             slot #slot of the witness table, and call it *)
          let pn = match vty ex with Types.TProto pn -> pn | _ -> assert false in
          let n = ex_words pn in
          let buf = Printf.sprintf "%%self%d" v in
          let arr = fresh () and tbl = fresh () and slotp = fresh () and fn = fresh () in
          p (Printf.sprintf "  %s = extractvalue %%any.%s %s, 0\n" arr pn (op ex));
          p (Printf.sprintf "  store [%d x i64] %s, ptr %s\n" n arr buf);
          p (Printf.sprintf "  %s = extractvalue %%any.%s %s, 1\n" tbl pn (op ex));
          p (Printf.sprintf "  %s = getelementptr ptr, ptr %s, i64 %d\n" slotp tbl slot);
          p (Printf.sprintf "  %s = load ptr, ptr %s\n" fn slotp);
          let argstr =
            String.concat ""
              (List.map (fun a -> Printf.sprintf ", %s %s" (llty (vty a)) (op a)) args)
          in
          let rt = vty v in
          if rt = Types.TVoid then p (Printf.sprintf "  call void %s(ptr %s%s)\n" fn buf argstr)
          else p (Printf.sprintf "  %s = call %s %s(ptr %s%s)\n" (op v) (llty rt) fn buf argstr)
    in
    let gen_term (t : Sil.term) =
      (* terminator arguments are consumed by the target blocks' phi nodes, so the branch itself
         just names labels *)
      match t with
      | Sil.Br (n, _) -> p (Printf.sprintf "  br label %%bb%d\n" n)
      | Sil.Cond_br (c, (th, _), (el, _)) ->
          p (Printf.sprintf "  br i1 %s, label %%bb%d, label %%bb%d\n" (op c) th el)
      | Sil.Return None -> p (if is_main then "  ret i32 0\n" else "  ret void\n")
      | Sil.Return (Some v) -> p (Printf.sprintf "  ret %s %s\n" (llty f.Sil.ret) (op v))
      | Sil.Unreachable -> p "  unreachable\n"
      | Sil.Trap msg ->
          let g = add_string_const (msg ^ "\n") in
          p (Printf.sprintf "  call i64 @write(i32 2, ptr %s, i64 %d)\n" g (String.length msg + 1));
          p "  call void @llvm.trap()\n";
          p "  unreachable\n"
    in
    (* a block: its label, a phi for each block argument, then the instructions and terminator *)
    let gen_phi (b : Sil.block) =
      let preds = try Hashtbl.find incoming b.Sil.bid with Not_found -> [] in
      List.iteri
        (fun i (av, at) ->
          let incs =
            List.map (fun (pred, args) -> Printf.sprintf "[ %s, %%bb%d ]" (op (List.nth args i)) pred) preds
          in
          p (Printf.sprintf "  %s = phi %s %s\n" (op av) (llty at) (String.concat ", " incs)))
        b.Sil.args
    in
    (* EVERY alloca goes at the top of the ENTRY block. An alloca only releases its stack space
       when the function returns — so an alloca inside a loop body grows the stack every iteration
       (a real segfault, caught by the concept-20 benchmark: 3M iterations × a struct slot).
       clang hoists allocas the same way; LLVM's mem2reg also only promotes entry-block allocas. *)
    let gen_allocas () =
      List.iter
        (fun (b : Sil.block) ->
          List.iter
            (fun (v, i) ->
              match (i : Sil.instr) with
              | Sil.Alloc_stack _ -> p (Printf.sprintf "  %s = alloca %s\n" (op v) (llty (vty v)))
              (* concept 21: each existential site gets a payload buffer (also entry-hoisted) *)
              | Sil.Init_existential (_, _, pn) ->
                  p (Printf.sprintf "  %%ex%d = alloca [%d x i64]\n" v (ex_words pn))
              | Sil.Apply_witness (ex, _, _) ->
                  let pn = match vty ex with Types.TProto pn -> pn | _ -> assert false in
                  p (Printf.sprintf "  %%self%d = alloca [%d x i64]\n" v (ex_words pn))
              | _ -> ())
            (List.rev b.Sil.instrs))
        (List.rev f.Sil.blocks)
    in
    List.iteri
      (fun i (b : Sil.block) ->
        p (Printf.sprintf "bb%d:\n" b.Sil.bid);
        gen_phi b;
        if i = 0 then gen_allocas ();
        List.iter gen_instr (List.rev b.Sil.instrs);
        gen_term b.Sil.term)
      (List.rev f.Sil.blocks);
    p "}\n\n"
  in
  List.iter gen_func m.Sil.funcs;
  (* LLVM named type for each struct: `%Point = type { i64, i64 }` (concept 10) *)
  let struct_defs =
    List.map
      (fun (sl : Types.struct_layout) ->
        Printf.sprintf "%%%s = type { %s }" sl.Types.sl_name
          (String.concat ", " (List.map (fun (_, t) -> llty t) sl.Types.sl_fields)))
      m.Sil.structs
  in
  (* LLVM named type for each enum: `%E = type { i64, i64×payload }` (tag + payload slots) *)
  let enum_defs =
    List.map
      (fun (el : Types.enum_layout) ->
        let slots = "i64" :: List.init (Types.max_payload el) (fun _ -> "i64") in
        Printf.sprintf "%%%s = type { %s }" el.Types.el_name (String.concat ", " slots))
      m.Sil.enums
  in
  (* LLVM named type for each protocol's existential: { payload buffer, witness-table ptr } *)
  let proto_defs =
    List.map
      (fun (pl : Types.proto_layout) ->
        Printf.sprintf "%%any.%s = type { [%d x i64], ptr }" pl.Types.pl_name (ex_words pl.Types.pl_name))
      m.Sil.protos
  in
  let type_defs = struct_defs @ enum_defs @ proto_defs in
  (* concept 21: one WITNESS TABLE per conformance — a global constant array of function
     pointers, one per requirement — plus a THUNK per entry. The thunk is the ABI adapter:
     dispatch sites pass `self` BY POINTER (they don't know the concrete type); the thunk
     loads the concrete struct out of the buffer and calls the real method directly. *)
  let wt_buf = Buffer.create 256 in
  List.iter
    (fun (pn, sn, fns) ->
      let pl = List.find (fun (pl : Types.proto_layout) -> pl.Types.pl_name = pn) m.Sil.protos in
      List.iteri
        (fun i fn ->
          let _, ptys, ret = List.nth pl.Types.pl_reqs i in
          let params = List.mapi (fun j t -> Printf.sprintf ", %s %%a%d" (llty t) j) ptys in
          let args = List.mapi (fun j t -> Printf.sprintf ", %s %%a%d" (llty t) j) ptys in
          Buffer.add_string wt_buf
            (Printf.sprintf "define private %s @w.%s.%s.%d(ptr %%self%s) {\n"
               (if ret = Types.TVoid then "void" else llty ret)
               pn sn i (String.concat "" params));
          Buffer.add_string wt_buf (Printf.sprintf "  %%self.v = load %%%s, ptr %%self\n" sn);
          (if ret = Types.TVoid then
             Buffer.add_string wt_buf
               (Printf.sprintf "  call void @%s(%%%s %%self.v%s)\n  ret void\n" fn sn (String.concat "" args))
           else (
             Buffer.add_string wt_buf
               (Printf.sprintf "  %%r = call %s @%s(%%%s %%self.v%s)\n" (llty ret) fn sn (String.concat "" args));
             Buffer.add_string wt_buf (Printf.sprintf "  ret %s %%r\n" (llty ret))));
          Buffer.add_string wt_buf "}\n")
        fns;
      let entries = List.mapi (fun i _ -> Printf.sprintf "ptr @w.%s.%s.%d" pn sn i) fns in
      Buffer.add_string wt_buf
        (Printf.sprintf "@wt.%s.%s = private unnamed_addr constant [%d x ptr] [%s]\n\n" pn sn
           (List.length fns) (String.concat ", " entries)))
    m.Sil.wtables;
  (* assemble: preamble + struct/enum types + string constants + functions *)
  let preamble =
    "; swiftml Phase-2 LLVM IR\n\
     declare i32 @printf(ptr, ...)\n\
     declare i64 @write(i32, ptr, i64)\n\
     declare void @llvm.trap()\n\
     @.fmt_int = private unnamed_addr constant [6 x i8] c\"%lld\\0A\\00\"\n\
     @.fmt_str = private unnamed_addr constant [4 x i8] c\"%s\\0A\\00\"\n\
     @.fmt_dbl = private unnamed_addr constant [4 x i8] c\"%g\\0A\\00\"\n\
     @.btrue  = private unnamed_addr constant [5 x i8] c\"true\\00\"\n\
     @.bfalse = private unnamed_addr constant [6 x i8] c\"false\\00\"\n"
  in
  preamble
  ^ (if type_defs = [] then "" else String.concat "\n" type_defs ^ "\n")
  ^ Buffer.contents globals ^ "\n" ^ Buffer.contents wt_buf ^ Buffer.contents out
