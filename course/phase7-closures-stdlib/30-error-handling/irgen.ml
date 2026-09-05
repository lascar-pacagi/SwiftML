(* IRGen for concept 29 (skeleton) — the closure ABI. Context construction, thunks, and the
   fn-value ARC are given; you emit the INDIRECT CALL (TODO(29b)). *)

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
  | Types.TClass _ -> "ptr" (* a class value IS a pointer to the heap object — concept 25 *)
  | Types.TFunc _ -> "%thickfn" (* { code ptr, context ptr } — concept 29 *)
  | Types.TVar (_, c) -> "%any." ^ c
    (* concept 22: an unspecialized generic T travels in its CONSTRAINT's existential rep
       (SILGen already erased TVar to TProto; this arm is belt-and-braces) *)

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
    | Types.TVar (_, c) -> 1 + ex_words c
    | Types.TClass _ -> 1
    | Types.TFunc _ -> 2
  (* concept 23: the existential container is FIXED-SIZE — a 3-word inline buffer plus the
     witness-table pointer, exactly swiftc's layout. A conformer that fits stays inline; a
     larger one is heap-BOXED: the buffer's first word holds a pointer to malloc'd storage.
     (21's whole-module max-sizing is gone — swiftc can't see all conformers across modules,
     and with boxing neither do we need to.) *)
  and ex_words (_pname : string) : int = 3 in
  let is_boxed (sname : string) : bool = words (Types.TStruct sname) > 3 in
  (* concept 25: a heap object = { ptr vtable, i64 refcount, fields... } — the refcount word is
     reserved for concept 26 (ARC); Alloc_ref initializes it to 1 *)
  let clay n = List.find (fun (cl : Types.class_layout) -> cl.Types.cl_name = n) m.Sil.classes in
  (* concept 29: a lifted closure's context layout *)
  let closure_caps n = List.assoc n m.Sil.closures in
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
      | t ->
          (* sema rejects printing an aggregate, so reaching here is a compiler bug,
             not a user error — say which type rather than dying in Match_failure *)
          failwith (Printf.sprintf "IRGen: print of unsupported type %s" (Types.string_of_ty t))
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
      (* generics — concept 22: open = copy the payload back out as the known concrete type *)
      | Sil.Open_existential (ex, sn) ->
          let pn = match vty ex with Types.TProto pn | Types.TVar (_, pn) -> pn | _ -> assert false in
          let n = ex_words pn in
          let buf = Printf.sprintf "%%open%d" v in
          let arr = fresh () in
          p (Printf.sprintf "  %s = extractvalue %%any.%s %s, 0\n" arr pn (op ex));
          p (Printf.sprintf "  store [%d x i64] %s, ptr %s\n" n arr buf);
          if is_boxed sn then (
            (* the buffer holds a POINTER to the boxed payload — follow it *)
            let bp = fresh () in
            p (Printf.sprintf "  %s = load ptr, ptr %s\n" bp buf);
            p (Printf.sprintf "  %s = load %%%s, ptr %s\n" (op v) sn bp))
          else p (Printf.sprintf "  %s = load %%%s, ptr %s\n" (op v) sn buf)
      (* closures — concept 29 *)
      | Sil.Closure (fn, caps) ->
          (* heap-allocate the context (an object: no-op destructor vtable + refcount), copy
             the captures in, pair it with the lifted function's code pointer *)
          let layout = closure_caps fn in
          let size = 16 + 8 * List.fold_left (fun a (_, t) -> a + words t) 0 layout in
          let ctx = fresh () and vp = fresh () and rp = fresh () and half = fresh () in
          p (Printf.sprintf "  %s = call ptr @malloc(i64 %d)\n" ctx size);
          p (Printf.sprintf "  %s = getelementptr %%ctx.%s, ptr %s, i32 0, i32 0\n" vp fn ctx);
          p (Printf.sprintf "  store ptr @vtbl.closure, ptr %s\n" vp);
          p (Printf.sprintf "  %s = getelementptr %%ctx.%s, ptr %s, i32 0, i32 1\n" rp fn ctx);
          p (Printf.sprintf "  store i64 1, ptr %s\n" rp);
          List.iteri
            (fun i cv ->
              let fp = fresh () in
              p (Printf.sprintf "  %s = getelementptr %%ctx.%s, ptr %s, i32 0, i32 %d\n" fp fn ctx (i + 2));
              p (Printf.sprintf "  store %s %s, ptr %s\n" (llty (vty cv)) (op cv) fp))
            caps;
          p (Printf.sprintf "  %s = insertvalue %%thickfn undef, ptr @%s, 0\n" half fn);
          p (Printf.sprintf "  %s = insertvalue %%thickfn %s, ptr %s, 1\n" (op v) half ctx)
      | Sil.Thin_to_thick fn ->
          (* a named function as a value: its context-taking THUNK + a null context *)
          let half = fresh () in
          p (Printf.sprintf "  %s = insertvalue %%thickfn undef, ptr @%s$thunk, 0\n" half fn);
          p (Printf.sprintf "  %s = insertvalue %%thickfn %s, ptr null, 1\n" (op v) half)
      | Sil.Apply_value (fv, args) ->
          (* the INDIRECT call — extract code+context from the %thickfn pair, call code with the
             context FIRST, then the args (concept 29) *)
          let code = fresh () and ctx = fresh () in
          p (Printf.sprintf "  %s = extractvalue %%thickfn %s, 0\n" code (op fv));
          p (Printf.sprintf "  %s = extractvalue %%thickfn %s, 1\n" ctx (op fv));
          let argstr =
            String.concat "" (List.map (fun a -> Printf.sprintf ", %s %s" (llty (vty a)) (op a)) args)
          in
          let rt = vty v in
          if rt = Types.TVoid then p (Printf.sprintf "  call void %s(ptr %s%s)\n" code ctx argstr)
          else p (Printf.sprintf "  %s = call %s %s(ptr %s%s)\n" (op v) (llty rt) code ctx argstr)
      | Sil.Capture_get (ctx, i) ->
          (* inside the lifted function f: index its own context layout *)
          let fp = fresh () in
          p (Printf.sprintf "  %s = getelementptr %%ctx.%s, ptr %s, i32 0, i32 %d\n" fp f.Sil.fname (op ctx) (i + 2));
          p (Printf.sprintf "  %s = load %s, ptr %s\n" (op v) (llty (vty v)) fp)
      (* ownership — concepts 26/27 *)
      | Sil.Copy_value o -> (
          match vty o with
          | Types.TFunc _ ->
              (* a function value's +1 lives on its CONTEXT (null for thin functions — the
                 runtime's null-guard makes that free); rebuild the same pair as the result *)
              let ctx = fresh () and code = fresh () and half = fresh () in
              p (Printf.sprintf "  %s = extractvalue %%thickfn %s, 1\n" ctx (op o));
              p (Printf.sprintf "  call void @rt.retain(ptr %s)\n" ctx);
              p (Printf.sprintf "  %s = extractvalue %%thickfn %s, 0\n" code (op o));
              p (Printf.sprintf "  %s = insertvalue %%thickfn undef, ptr %s, 0\n" half code);
              p (Printf.sprintf "  %s = insertvalue %%thickfn %s, ptr %s, 1\n" (op v) half ctx)
          | _ ->
              (* a class copy IS a retain; the new SIL value is the same pointer *)
              p (Printf.sprintf "  call void @rt.retain(ptr %s)\n" (op o));
              p (Printf.sprintf "  %s = getelementptr i8, ptr %s, i64 0\n" (op v) (op o)))
      | Sil.Destroy_value o -> (
          match vty o with
          | Types.TFunc _ ->
              let ctx = fresh () in
              p (Printf.sprintf "  %s = extractvalue %%thickfn %s, 1\n" ctx (op o));
              p (Printf.sprintf "  call void @rt.release(ptr %s)\n" ctx)
          | _ -> p (Printf.sprintf "  call void @rt.release(ptr %s)\n" (op o)))
      | Sil.Load_take a ->
          (* ownership moves out of the slot — a plain load, no refcount traffic *)
          p (Printf.sprintf "  %s = load %s, ptr %s\n" (op v) (llty (vty v)) (op a))
      (* classes — concept 25 *)
      | Sil.Alloc_ref cn ->
          let cl = clay cn in
          let size = 8 * (2 + List.length cl.Types.cl_fields) in
          let vp = fresh () and rp = fresh () in
          p (Printf.sprintf "  %s = call ptr @malloc(i64 %d)\n" (op v) size);
          p (Printf.sprintf "  %s = getelementptr %%obj.%s, ptr %s, i32 0, i32 0\n" vp cn (op v));
          p (Printf.sprintf "  store ptr @vtbl.%s, ptr %s\n" cn vp);
          p (Printf.sprintf "  %s = getelementptr %%obj.%s, ptr %s, i32 0, i32 1\n" rp cn (op v));
          p (Printf.sprintf "  store i64 1, ptr %s\n" rp)
      | Sil.Ref_element_addr (o, idx) ->
          let cn = match vty o with Types.TClass cn -> cn | _ -> assert false in
          p (Printf.sprintf "  %s = getelementptr %%obj.%s, ptr %s, i32 0, i32 %d\n" (op v) cn (op o) (idx + 2))
      | Sil.Apply_class (o, slot, args) ->
          let vt = fresh () and sp = fresh () and fn = fresh () in
          p (Printf.sprintf "  %s = load ptr, ptr %s\n" vt (op o)); (* word 0 = the vtable ptr *)
          p (Printf.sprintf "  %s = getelementptr ptr, ptr %s, i64 %d\n" sp vt (slot + 2));
          (* +2: vtable slots 0/1 are the deinit-body and field-destroy chains (concept 26) *)
          p (Printf.sprintf "  %s = load ptr, ptr %s\n" fn sp);
          let argstr =
            String.concat "" (List.map (fun a -> Printf.sprintf ", %s %s" (llty (vty a)) (op a)) args)
          in
          let rt = vty v in
          if rt = Types.TVoid then p (Printf.sprintf "  call void %s(ptr %s%s)\n" fn (op o) argstr)
          else p (Printf.sprintf "  %s = call %s %s(ptr %s%s)\n" (op v) (llty rt) fn (op o) argstr)
      | Sil.Upcast (o, _) ->
          (* same pointer, new static type — an identity GEP keeps emission uniform *)
          p (Printf.sprintf "  %s = getelementptr i8, ptr %s, i64 0\n" (op v) (op o))
      (* dynamic casts — concept 23: type identity IS witness-table identity *)
      | Sil.Same_witness (ex, sn) ->
          let pn = match vty ex with Types.TProto pn | Types.TVar (_, pn) -> pn | _ -> assert false in
          let tbl = fresh () in
          p (Printf.sprintf "  %s = extractvalue %%any.%s %s, 1\n" tbl pn (op ex));
          p (Printf.sprintf "  %s = icmp eq ptr %s, @wt.%s.%s\n" (op v) tbl pn sn)
      (* protocols — concept 21 *)
      | Sil.Init_existential (pv, sn, pn) ->
          (* a fitting value is stored INLINE in this site's 3-word buffer; a large one is
             heap-boxed and the buffer's first word holds the box pointer (concept 23) *)
          let n = ex_words pn in
          let buf = Printf.sprintf "%%ex%d" v in
          let arr = fresh () and half = fresh () in
          (if is_boxed sn then (
             let box = fresh () in
             p (Printf.sprintf "  %s = call ptr @malloc(i64 %d)\n" box (8 * words (Types.TStruct sn)));
             p (Printf.sprintf "  store %%%s %s, ptr %s\n" sn (op pv) box);
             p (Printf.sprintf "  store ptr %s, ptr %s\n" box buf))
           else p (Printf.sprintf "  store %%%s %s, ptr %s\n" sn (op pv) buf));
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
      (* a Void function whose terminator still carries a value — a single-expression closure
         body of type `()`, `{ (x: Int) -> Void in print(x) }` — returns nothing: `ret void %v`
         is not LLVM *)
      | Sil.Return (Some _) when f.Sil.ret = Types.TVoid -> p "  ret void\n"
      | Sil.Return (Some v) -> p (Printf.sprintf "  ret %s %s\n" (llty f.Sil.ret) (op v))
      | Sil.Unreachable -> p "  unreachable\n"
      | Sil.Trap msg ->
          let g = add_string_const (msg ^ "\n") in
          p (Printf.sprintf "  call i64 @write(i32 2, ptr %s, i64 %d)\n" g (String.length msg + 1));
          p "  call void @llvm.trap()\n";
          p "  unreachable\n"
      | Sil.Abort msg ->
          (* a failed `as!`: swiftc aborts (SIGABRT, exit 134) — so do we (concept 23) *)
          let g = add_string_const (msg ^ "\n") in
          p (Printf.sprintf "  call i64 @write(i32 2, ptr %s, i64 %d)\n" g (String.length msg + 1));
          p "  call void @abort()\n";
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
                  let pn = match vty ex with Types.TProto pn | Types.TVar (_, pn) -> pn | _ -> assert false in
                  p (Printf.sprintf "  %%self%d = alloca [%d x i64]\n" v (ex_words pn))
              | Sil.Open_existential (ex, _) ->
                  let pn = match vty ex with Types.TProto pn | Types.TVar (_, pn) -> pn | _ -> assert false in
                  p (Printf.sprintf "  %%open%d = alloca [%d x i64]\n" v (ex_words pn))
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
  (* concept 25: the heap-object layout of each class — header (vtable ptr, refcount) + fields *)
  let class_defs =
    List.map
      (fun (cl : Types.class_layout) ->
        let fields = List.map (fun (_, t) -> llty t) cl.Types.cl_fields in
        Printf.sprintf "%%obj.%s = type { ptr, i64%s }" cl.Types.cl_name
          (String.concat "" (List.map (fun f -> ", " ^ f) fields)))
      m.Sil.classes
  in
  (* concept 29: the universal thick-function pair + one context type per lifted closure *)
  let closure_defs =
    "%thickfn = type { ptr, ptr }"
    :: List.map
         (fun (fn, caps) ->
           Printf.sprintf "%%ctx.%s = type { ptr, i64%s }" fn
             (String.concat "" (List.map (fun (_, t) -> ", " ^ llty t) caps)))
         m.Sil.closures
  in
  let type_defs = struct_defs @ enum_defs @ proto_defs @ class_defs @ closure_defs in
  (* thunks: every named function used as a value gets a context-taking wrapper *)
  let thunk_targets = Hashtbl.create 8 in
  List.iter
    (fun (f : Sil.func) ->
      List.iter
        (fun (b : Sil.block) ->
          List.iter
            (fun (_, i) -> match i with Sil.Thin_to_thick fn -> Hashtbl.replace thunk_targets fn () | _ -> ())
            b.Sil.instrs)
        f.Sil.blocks)
    m.Sil.funcs;
  let thunk_buf = Buffer.create 128 in
  Hashtbl.iter
    (fun fn () ->
      match List.find_opt (fun (f : Sil.func) -> f.Sil.fname = fn) m.Sil.funcs with
      | Some f ->
          let params = List.mapi (fun i (_, t) -> Printf.sprintf ", %s %%a%d" (llty t) i) f.Sil.params in
          let args = List.mapi (fun i (_, t) -> Printf.sprintf "%s %%a%d" (llty t) i) f.Sil.params in
          let rt = if f.Sil.ret = Types.TVoid then "void" else llty f.Sil.ret in
          Buffer.add_string thunk_buf
            (Printf.sprintf "define private %s @%s$thunk(ptr %%ctx%s) {\n" rt fn (String.concat "" params));
          if f.Sil.ret = Types.TVoid then
            Buffer.add_string thunk_buf (Printf.sprintf "  call void @%s(%s)\n  ret void\n}\n" fn (String.concat ", " args))
          else (
            Buffer.add_string thunk_buf
              (Printf.sprintf "  %%r = call %s @%s(%s)\n" rt fn (String.concat ", " args));
            Buffer.add_string thunk_buf (Printf.sprintf "  ret %s %%r\n}\n" rt))
      | None -> ())
    thunk_targets;
  Buffer.add_string thunk_buf
    "define private void @closure.noop(ptr %o) {\n  ret void\n}\n@vtbl.closure = private unnamed_addr constant [2 x ptr] [ptr @closure.noop, ptr @closure.noop]\n\n";
  (* one VTABLE per class: a global constant array of method pointers in slot order *)
  let vt_buf = Buffer.create 256 in
  List.iter
    (fun (cl : Types.class_layout) ->
      (* slot 0 = the deinit-BODY chain, slot 1 = the field-DESTROY chain (concept 26: the
         runtime runs both, in that order, at refcount zero); SIL method slots shift by two *)
      let entries =
        ("ptr @" ^ cl.Types.cl_name ^ ".deinit")
        :: ("ptr @" ^ cl.Types.cl_name ^ ".destroy")
        :: List.map (fun fn -> "ptr @" ^ fn) cl.Types.cl_impls
      in
      Buffer.add_string vt_buf
        (Printf.sprintf "@vtbl.%s = private unnamed_addr constant [%d x ptr] [%s]\n" cl.Types.cl_name
           (List.length entries) (String.concat ", " entries)))
    m.Sil.classes;
  Buffer.add_string vt_buf "\n";
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
          (if is_boxed sn then (
             Buffer.add_string wt_buf "  %boxp = load ptr, ptr %self\n";
             Buffer.add_string wt_buf (Printf.sprintf "  %%self.v = load %%%s, ptr %%boxp\n" sn))
           else Buffer.add_string wt_buf (Printf.sprintf "  %%self.v = load %%%s, ptr %%self\n" sn));
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
     declare void @abort()\n\
     declare ptr @malloc(i64)\n\
     declare void @free(ptr)\n\
     @.fmt_int = private unnamed_addr constant [6 x i8] c\"%lld\\0A\\00\"\n\
     @.fmt_str = private unnamed_addr constant [4 x i8] c\"%s\\0A\\00\"\n\
     @.fmt_dbl = private unnamed_addr constant [4 x i8] c\"%g\\0A\\00\"\n\
     @.btrue  = private unnamed_addr constant [5 x i8] c\"true\\00\"\n\
     @.bfalse = private unnamed_addr constant [6 x i8] c\"false\\00\"\n"
  in
  (* the ARC runtime — concept 26. retain: count up. release: count down; at zero, call the
     object's DESTRUCTOR (vtable slot 0: deinit body, field releases, super chain) then free. *)
  let arc_runtime =
    String.concat "\n"
      [ (* error handling — concept 30: a single global error register + its two intrinsics. The
           ordinal 0 = "no error"; a throw stores a positive case ordinal; every throwing call
           reads it back. (Single-threaded, so one global suffices — swiftc uses a register.) *)
        "@swiftml.error = internal global i64 0";
        "define private i64 @rt.error_get() {";
        "  %e = load i64, ptr @swiftml.error";
        "  ret i64 %e";
        "}";
        "define private void @rt.error_set(i64 %o) {";
        "  store i64 %o, ptr @swiftml.error";
        "  ret void";
        "}";
        "define private void @rt.retain(ptr %o) {";
        "  %isnull = icmp eq ptr %o, null";
        "  br i1 %isnull, label %skip, label %doit";
        "skip:";
        "  ret void";
        "doit:";
        "  %rcp = getelementptr i8, ptr %o, i64 8";
        "  %rc = load i64, ptr %rcp";
        "  %n = add i64 %rc, 1";
        "  store i64 %n, ptr %rcp";
        "  ret void";
        "}";
        "define private void @rt.release(ptr %o) {";
        "  %isnull = icmp eq ptr %o, null";
        "  br i1 %isnull, label %skip, label %doit";
        "skip:";
        "  ret void";
        "doit:";
        "  %rcp = getelementptr i8, ptr %o, i64 8";
        "  %rc = load i64, ptr %rcp";
        "  %n = sub i64 %rc, 1";
        "  store i64 %n, ptr %rcp";
        "  %z = icmp eq i64 %n, 0";
        "  br i1 %z, label %dead, label %done";
        "dead:";
        "  %vt = load ptr, ptr %o";
        "  %dtor = load ptr, ptr %vt";
        "  call void %dtor(ptr %o)"; (* the deinit-body chain, derived -> base *)
        "  %dsp = getelementptr ptr, ptr %vt, i64 1";
        "  %dstr = load ptr, ptr %dsp";
        "  call void %dstr(ptr %o)"; (* the field-destroy chain, base -> derived *)
        "  call void @free(ptr %o)";
        "  br label %done";
        "done:";
        "  ret void";
        "}";
        "" ]
  in
  preamble ^ arc_runtime
  ^ (if type_defs = [] then "" else String.concat "\n" type_defs ^ "\n")
  ^ Buffer.contents globals ^ "\n" ^ Buffer.contents vt_buf ^ Buffer.contents wt_buf
  ^ Buffer.contents thunk_buf ^ Buffer.contents out
