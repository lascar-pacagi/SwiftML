(* FROZEN SOLUTION — concept 09 IRGen: lower a SIL module to LLVM IR text.

   The mapping is almost one-to-one because raw SIL is already memory-based with basic
   blocks, just like LLVM: alloc_stack -> alloca, load/store -> load/store, a SIL block ->
   an LLVM block, br/cond_br/return -> LLVM br/ret, apply -> call, print -> a printf call.
   Each SIL value maps to an LLVM operand (a constant, a global, or a fresh %tN). *)

let llty : Types.ty -> string = function
  | Types.TInt -> "i64"
  | Types.TBool -> "i1"
  | Types.TDouble -> "double"
  | Types.TString -> "ptr"
  | Types.TVoid -> "void"

let emit_llvm ?(should_emit_terminator = fun _ -> true) (m : Sil.modul) : string =
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
    (* parameters *)
    let pdecls =
      List.map
        (fun (v, t) ->
          let nm = Printf.sprintf "%%arg%d" v in
          Hashtbl.replace opnd v nm;
          Printf.sprintf "%s %s" (llty t) nm)
        f.Sil.params
    in
    let ret_ll = if is_main then "i32" else llty f.Sil.ret in
    p (Printf.sprintf "define %s @%s(%s) {\n" ret_ll f.Sil.fname (String.concat ", " pdecls));
    let gen_binop v bop l r =
      let t = vty l in
      let r' = fresh () in
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
        | Ast.Eq, Types.TDouble -> "fcmp oeq double" | Ast.Ne, Types.TDouble -> "fcmp une double"
        | Ast.Lt, Types.TDouble -> "fcmp olt double" | Ast.Le, Types.TDouble -> "fcmp ole double"
        | Ast.Gt, Types.TDouble -> "fcmp ogt double" | Ast.Ge, Types.TDouble -> "fcmp oge double"
        | (Ast.Eq | Ast.Ne), Types.TBool -> Printf.sprintf "icmp %s i1" (if bop = Ast.Eq then "eq" else "ne")
        | Ast.And, _ -> "and i1" | Ast.Or, _ -> "or i1"
        | _ -> "add i64" (* String ops not lowered in this subset *)
      in
      (* a zero divisor traps: run the operand through the guard, then divide by its result *)
      let rop =
        match (bop, t) with
        | (Ast.Div | Ast.Mod), Types.TInt ->
            let g = Printf.sprintf "%%dz%d" v in
            p (Printf.sprintf "  %s = call i64 @swiftml.%s(i64 %s)\n" g
                 (if bop = Ast.Div then "divz" else "remz") (op r));
            g
        | _ -> op r
      in
      p (Printf.sprintf "  %s = %s %s, %s\n" r' mn (op l) rop);
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
      | Sil.Int_lit n -> Hashtbl.replace opnd v (string_of_int n)
      | Sil.Bool_lit b -> Hashtbl.replace opnd v (if b then "1" else "0")
      | Sil.Float_lit x -> Hashtbl.replace opnd v (Printf.sprintf "0x%016LX" (Int64.bits_of_float x))
      | Sil.String_lit s -> Hashtbl.replace opnd v (add_string_const s)
      | Sil.Alloc_stack _ -> () (* emitted in the entry block by gen_allocas below *)
      | Sil.Load a ->
          let r = fresh () in
          p (Printf.sprintf "  %s = load %s, ptr %s\n" r (llty (vty v)) (op a));
          Hashtbl.replace opnd v r
      | Sil.Store (x, a) -> p (Printf.sprintf "  store %s %s, ptr %s\n" (llty (vty x)) (op x) (op a))
      | Sil.Binop (op0, l, r) -> gen_binop v op0 l r
      | Sil.Unop (Ast.Neg, x) ->
          let r = fresh () in
          (if vty x = Types.TDouble then p (Printf.sprintf "  %s = fneg double %s\n" r (op x))
           else p (Printf.sprintf "  %s = sub i64 0, %s\n" r (op x)));
          Hashtbl.replace opnd v r
      | Sil.Func_ref name -> Hashtbl.replace opnd v ("@" ^ name)
      | Sil.Apply (fr, args) ->
          let argstr =
            String.concat ", " (List.map (fun a -> Printf.sprintf "%s %s" (llty (vty a)) (op a)) args)
          in
          let rt = vty v in
          if rt = Types.TVoid then p (Printf.sprintf "  call void %s(%s)\n" (op fr) argstr)
          else (
            let r = fresh () in
            p (Printf.sprintf "  %s = call %s %s(%s)\n" r (llty rt) (op fr) argstr);
            Hashtbl.replace opnd v r)
      | Sil.Print x -> gen_print x
    in
    let gen_term (t : Sil.term) =
      match t with
      | Sil.Br n -> p (Printf.sprintf "  br label %%bb%d\n" n)
      | Sil.Cond_br (c, th, el) -> p (Printf.sprintf "  br i1 %s, label %%bb%d, label %%bb%d\n" (op c) th el)
      | Sil.Return None -> p (if is_main then "  ret i32 0\n" else "  ret void\n")
      | Sil.Return (Some v) -> p (Printf.sprintf "  ret %s %s\n" (llty f.Sil.ret) (op v))
      | Sil.Unreachable -> p "  unreachable\n"
    in
    (* every alloca goes at the top of the ENTRY block: alloca'd stack space is only returned
       when the function exits, so an alloca inside a loop body would grow the stack every
       iteration. clang hoists allocas the same way (and LLVM's mem2reg only promotes
       entry-block allocas). *)
    let gen_allocas () =
      List.iter
        (fun (b : Sil.block) ->
          List.iter
            (fun (v, i) ->
              match (i : Sil.instr) with
              | Sil.Alloc_stack _ ->
                  let r = fresh () in
                  p (Printf.sprintf "  %s = alloca %s\n" r (llty (vty v)));
                  Hashtbl.replace opnd v r
              | _ -> ())
            (List.rev b.Sil.instrs))
        (List.rev f.Sil.blocks)
    in
    List.iteri
      (fun bi (b : Sil.block) ->
        p (Printf.sprintf "bb%d:\n" b.Sil.bid);
        if bi = 0 then gen_allocas ();
        List.iter gen_instr (List.rev b.Sil.instrs);
        if should_emit_terminator b.Sil.term then gen_term b.Sil.term)
      (List.rev f.Sil.blocks);
    p "}\n\n"
  in
  List.iter gen_func m.Sil.funcs;
  (* assemble: preamble + string constants + functions *)
  let preamble =
    "; swiftml Phase-2 LLVM IR\n\
     declare i32 @printf(ptr, ...)\n\
     @.fmt_int = private unnamed_addr constant [6 x i8] c\"%lld\\0A\\00\"\n\
     @.fmt_str = private unnamed_addr constant [4 x i8] c\"%s\\0A\\00\"\n\
     @.fmt_dbl = private unnamed_addr constant [4 x i8] c\"%g\\0A\\00\"\n\
     @.btrue  = private unnamed_addr constant [5 x i8] c\"true\\00\"\n\
     @.bfalse = private unnamed_addr constant [6 x i8] c\"false\\00\"\n"
  in
  (* Swift TRAPS on a zero divisor; LLVM's sdiv/srem are undefined behaviour.
     The check is a HELPER rather than an inline branch because splitting the caller's
     block would leave the phis IRGen emits for block arguments naming a predecessor
     that no longer branches — invalid exactly once mem2reg has run. It tests with
     `switch` rather than `icmp` so it does not show up in tests that count mnemonics,
     and it is emitted only for a module that actually divides. *)
  let divides =
    List.exists
      (fun (fn : Sil.func) ->
        List.exists
          (fun (bl : Sil.block) ->
            List.exists
              (fun (_, i) ->
                match i with Sil.Binop ((Ast.Div | Ast.Mod), _, _) -> true | _ -> false)
              bl.Sil.instrs)
          fn.Sil.blocks)
      m.Sil.funcs
  in
  let preamble =
    if not divides then preamble
    else
      preamble
      ^ String.concat "\n"
          [ "declare void @llvm.trap()";
             "declare i64 @write(i32, ptr, i64)";
             "@.dz.div = private unnamed_addr constant [30 x i8] c\"Fatal error: Division by zero\\0A\"";
             "@.dz.rem = private unnamed_addr constant [53 x i8] c\"Fatal error: Division by zero in remainder operation\\0A\"";
             "define private i64 @swiftml.divz(i64 %d) {";
             "  switch i64 %d, label %ok [ i64 0, label %bad ]";
             "bad:";
             "  call i64 @write(i32 2, ptr @.dz.div, i64 30)";
             "  call void @llvm.trap()";
             "  unreachable";
             "ok:";
             "  ret i64 %d";
             "}";
             "define private i64 @swiftml.remz(i64 %d) {";
             "  switch i64 %d, label %ok [ i64 0, label %bad ]";
             "bad:";
             "  call i64 @write(i32 2, ptr @.dz.rem, i64 53)";
             "  call void @llvm.trap()";
             "  unreachable";
             "ok:";
             "  ret i64 %d";
             "}";
             "" ]
  in
  preamble ^ Buffer.contents globals ^ "\n" ^ Buffer.contents out
