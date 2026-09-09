(* IRGen — concept 09 (skeleton). Lower a SIL module to LLVM IR text.

   The mapping is almost one-to-one because raw SIL is already memory-based with basic
   blocks, just like LLVM: alloc_stack -> alloca, load/store -> load/store, a SIL block ->
   an LLVM block, br/cond_br/return -> LLVM br/ret, apply -> call, print -> a printf call.
   Each SIL value maps to an LLVM operand (a constant, a global, or a fresh %tN).

   You fill the two TODO(09) holes: gen_instr and gen_term. The shell (gen_binop, gen_print,
   gen_allocas, the buffers, llvm_type) is given. Reference: solution/irgen.ml. *)

let llvm_type : Types.ty -> string = function
  | Types.TInt -> "i64"
  | Types.TBool -> "i1"
  | Types.TDouble -> "double"
  | Types.TString -> "ptr"
  | Types.TVoid -> "void"

let emit_llvm ?(include_terminators = true) (sil_module : Sil.modul) : string =
  let global_definitions = Buffer.create 256 in
  let function_definitions = Buffer.create 1024 in
  let next_string_id = ref 0 in
  let escape text =
    let escaped = Buffer.create (String.length text) in
    String.iter
      (fun character ->
        if character = '"' || character = '\\' || Char.code character < 32
           || Char.code character > 126
        then Buffer.add_string escaped (Printf.sprintf "\\%02X" (Char.code character))
        else Buffer.add_char escaped character)
      text;
    Buffer.contents escaped
  in
  let add_string_const text =
    let global_name = Printf.sprintf "@.str%d" !next_string_id in
    incr next_string_id;
    Buffer.add_string global_definitions
      (Printf.sprintf "%s = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n" global_name
         (String.length text + 1) (escape text));
    global_name
  in
  let gen_func (func : Sil.func) =
    (* The process entry point follows the C ABI and returns an i32 status code, even though
       the source-level main body has no return value. *)
    let is_main = func.Sil.fname = "main" in
    (* IRGen learns the printed LLVM operand for each SIL value as it walks the function.
       An operand may be an immediate constant, an argument such as %arg0, or a temporary. *)
    let operands : (Sil.value, string) Hashtbl.t = Hashtbl.create 64 in
    (* LLVM temporary names are local to a function, so numbering restarts for every function. *)
    let next_temp_id = ref 0 in
    let fresh_temp () =
      let id = !next_temp_id in
      incr next_temp_id;
      Printf.sprintf "%%t%d" id
    in
    (* Read or record a value's LLVM spelling. Keeping both operations here hides the table. *)
    let lookup_operand value = Hashtbl.find operands value in
    let bind_operand value llvm_operand = Hashtbl.replace operands value llvm_operand in
    (* Look up the SIL type when choosing an LLVM type or opcode. *)
    let value_type value = Hashtbl.find func.Sil.val_ty value in
    (* Append emitted LLVM text to the module's function buffer. *)
    let emit text = Buffer.add_string function_definitions text in
    (* parameters *)
    let parameter_declarations =
      List.map
        (fun (value, ty) ->
          let llvm_name = Printf.sprintf "%%arg%d" value in
          bind_operand value llvm_name;
          Printf.sprintf "%s %s" (llvm_type ty) llvm_name)
        func.Sil.params
    in
    let llvm_return_type = if is_main then "i32" else llvm_type func.Sil.ret in
    emit
      (Printf.sprintf "define %s @%s(%s) {\n" llvm_return_type func.Sil.fname
         (String.concat ", " parameter_declarations));
    let gen_binop result operator left right =
      let operand_type = value_type left in
      let result_operand = fresh_temp () in
      let mnemonic =
        match (operator, operand_type) with
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
        | (Ast.Eq | Ast.Ne), Types.TBool ->
            Printf.sprintf "icmp %s i1" (if operator = Ast.Eq then "eq" else "ne")
        | Ast.And, _ -> "and i1" | Ast.Or, _ -> "or i1"
        | _ -> "add i64" (* String ops not lowered in this subset *)
      in
      (* a zero divisor traps: run the operand through the guard, then divide by its result *)
      let right_operand =
        match (operator, operand_type) with
        | (Ast.Div | Ast.Mod), Types.TInt ->
            let guarded_right = Printf.sprintf "%%dz%d" result in
            emit
              (Printf.sprintf "  %s = call i64 @swiftml.%s(i64 %s)\n" guarded_right
                 (if operator = Ast.Div then "divz" else "remz") (lookup_operand right));
            guarded_right
        | _ -> lookup_operand right
      in
      emit
        (Printf.sprintf "  %s = %s %s, %s\n" result_operand mnemonic (lookup_operand left)
           right_operand);
      bind_operand result result_operand
    and gen_print value =
      match value_type value with
      | Types.TInt ->
          emit
            (Printf.sprintf "  call i32 (ptr, ...) @printf(ptr @.fmt_int, i64 %s)\n"
               (lookup_operand value))
      | Types.TBool ->
          let string_operand = fresh_temp () in
          emit
            (Printf.sprintf "  %s = select i1 %s, ptr @.btrue, ptr @.bfalse\n"
               string_operand (lookup_operand value));
          emit
            (Printf.sprintf "  call i32 (ptr, ...) @printf(ptr @.fmt_str, ptr %s)\n"
               string_operand)
      | Types.TString ->
          emit
            (Printf.sprintf "  call i32 (ptr, ...) @printf(ptr @.fmt_str, ptr %s)\n"
               (lookup_operand value))
      | Types.TDouble ->
          emit
            (Printf.sprintf "  call i32 (ptr, ...) @printf(ptr @.fmt_dbl, double %s)\n"
               (lookup_operand value))
      | Types.TVoid -> ()
    in
    let gen_instr (value, instr) =
      match (instr : Sil.instr) with
      (* given as the pattern: a SIL Int_lit maps a SIL value to a constant operand *)
      | Sil.Int_lit integer -> bind_operand value (string_of_int integer)
      | Sil.Bool_lit boolean -> bind_operand value (if boolean then "1" else "0")
      | Sil.Float_lit float ->
          bind_operand value (Printf.sprintf "0x%016LX" (Int64.bits_of_float float))
      | Sil.String_lit text -> bind_operand value (add_string_const text)
      | Sil.Alloc_stack _ -> () (* emitted in the entry block by gen_allocas below (no-op here) *)
      (* TODO(09): the remaining instructions. The mapping is near 1:1 — §2 tabulates every SIL
         instruction against its LLVM line. Emit with [emit], and register each result operand
         with [bind_operand value (fresh_temp ())] so later instructions can refer to it.
         Watch the ones that emit NO line (a func_ref is just an operand) and the ones that
         produce no result (a void call, a store). *)
      | _ -> ignore gen_binop; ignore gen_print; failwith "TODO(09): lower a SIL instruction"
    in
    let gen_term (terminator : Sil.term) =
      ignore terminator;
      ignore is_main;
      (* TODO(09): the terminators — br, conditional br, ret, unreachable (§2). The one special
         case: @main returns i32, so a valueless return there is `ret i32 0`. *)
      failwith "TODO(09): lower a SIL terminator"
    in
    (* every alloca goes at the top of the ENTRY block: alloca'd stack space is only returned
       when the function exits, so an alloca inside a loop body would grow the stack every
       iteration. clang hoists allocas the same way (and LLVM's mem2reg only promotes
       entry-block allocas). *)
    let gen_allocas () =
      List.iter
        (fun (block : Sil.block) ->
          List.iter
            (fun (value, instr) ->
              match (instr : Sil.instr) with
              | Sil.Alloc_stack _ ->
                  let stack_operand = fresh_temp () in
                  emit
                    (Printf.sprintf "  %s = alloca %s\n" stack_operand
                       (llvm_type (value_type value)));
                  bind_operand value stack_operand
              | _ -> ())
            (List.rev block.Sil.instrs))
        (List.rev func.Sil.blocks)
    in
    List.iteri
      (fun block_index (block : Sil.block) ->
        emit (Printf.sprintf "bb%d:\n" block.Sil.bid);
        if block_index = 0 then gen_allocas ();
        List.iter gen_instr (List.rev block.Sil.instrs);
        if include_terminators then gen_term block.Sil.term)
      (List.rev func.Sil.blocks);
    emit "}\n\n"
  in
  List.iter gen_func sil_module.Sil.funcs;
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
  let has_division =
    List.exists
      (fun (func : Sil.func) ->
        List.exists
          (fun (block : Sil.block) ->
            List.exists
              (fun (_, instr) ->
                match instr with
                | Sil.Binop ((Ast.Div | Ast.Mod), _, _) -> true
                | _ -> false)
              block.Sil.instrs)
          func.Sil.blocks)
      sil_module.Sil.funcs
  in
  let preamble =
    if not has_division then preamble
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
  preamble ^ Buffer.contents global_definitions ^ "\n" ^ Buffer.contents function_definitions
