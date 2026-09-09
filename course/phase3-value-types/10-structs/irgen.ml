(* IRGen — concept 10 (skeleton). Carries Phase-2 IRGen complete; you add the STRUCT
   instructions in TODO(10i). Lower a SIL module to LLVM IR text.

   The mapping is almost one-to-one because raw SIL is already memory-based with basic
   blocks, just like LLVM: alloc_stack -> alloca, load/store -> load/store, a SIL block ->
   an LLVM block, br/cond_br/return -> LLVM br/ret, apply -> call, print -> a printf call.
   Each SIL value maps to an LLVM operand (a constant, a global, or a fresh %tN). *)

let llvm_type : Types.ty -> string = function
  | Types.TInt -> "i64"
  | Types.TBool -> "i1"
  | Types.TDouble -> "double"
  | Types.TString -> "ptr"
  | Types.TVoid -> "void"
  | Types.TStruct name -> "%" ^ name (* an LLVM named aggregate type — concept 10 *)

let emit_llvm (sil_module : Sil.modul) : string =
  let global_definitions = Buffer.create 256 in
  let function_definitions = Buffer.create 1024 in
  let next_string_id = ref 0 in
  let escape text =
    let escaped = Buffer.create (String.length text) in
    String.iter
      (fun character ->
        if character = '"' || character = '\\'
           || Char.code character < 32 || Char.code character > 126
        then
          Buffer.add_string escaped
            (Printf.sprintf "\\%02X" (Char.code character))
        else Buffer.add_char escaped character)
      text;
    Buffer.contents escaped
  in
  let add_string_const text =
    let global_name = Printf.sprintf "@.str%d" !next_string_id in
    incr next_string_id;
    Buffer.add_string global_definitions
      (Printf.sprintf "%s = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
         global_name (String.length text + 1) (escape text));
    global_name
  in
  let gen_function (function_definition : Sil.func) =
    (* LLVM gives the process entry point a C-compatible signature. *)
    let is_main = function_definition.Sil.fname = "main" in
    (* A SIL value number names different things in LLVM: a literal, an argument,
       a global string, a stack slot, or an SSA temporary. Record that mapping here. *)
    let operands : (Sil.value, string) Hashtbl.t = Hashtbl.create 64 in
    (* LLVM temporary names are local to a function, so numbering restarts here. *)
    let next_temp_id = ref 0 in
    let fresh_temp () =
      let temp_id = !next_temp_id in
      incr next_temp_id;
      Printf.sprintf "%%t%d" temp_id
    in
    (* Instructions use these helpers instead of touching the table directly. *)
    let lookup_operand value = Hashtbl.find operands value in
    let bind_operand value llvm_operand =
      Hashtbl.replace operands value llvm_operand
    in
    (* SILGen already computed every value's type. IRGen only translates it. *)
    let value_type value = Hashtbl.find function_definition.Sil.val_ty value in
    (* Accumulate the function text; global strings use the other buffer above. *)
    let emit text = Buffer.add_string function_definitions text in
    let parameter_declarations =
      List.map
        (fun (value, parameter_type) ->
          let llvm_name = Printf.sprintf "%%arg%d" value in
          bind_operand value llvm_name;
          Printf.sprintf "%s %s" (llvm_type parameter_type) llvm_name)
        function_definition.Sil.params
    in
    let llvm_return_type = if is_main then "i32" else llvm_type function_definition.Sil.ret in
    emit
      (Printf.sprintf "define %s @%s(%s) {\n" llvm_return_type function_definition.Sil.fname
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
        | Ast.Eq, Types.TDouble -> "fcmp oeq double" | Ast.Ne, Types.TDouble -> "fcmp une double"
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
                 (if operator = Ast.Div then "divz" else "remz")
                 (lookup_operand right));
            guarded_right
        | _ -> lookup_operand right
      in
      emit
        (Printf.sprintf "  %s = %s %s, %s\n" result_operand mnemonic
           (lookup_operand left) right_operand);
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
      | unsupported_type ->
          (* sema rejects printing an aggregate, so reaching here is a compiler bug,
             not a user error — say which type rather than dying in Match_failure *)
          failwith
            (Printf.sprintf "IRGen: print of unsupported type %s"
               (Types.string_of_ty unsupported_type))
    in
    let gen_instruction (value, instruction) =
      match (instruction : Sil.instr) with
      | Sil.Int_lit integer -> bind_operand value (string_of_int integer)
      | Sil.Bool_lit boolean -> bind_operand value (if boolean then "1" else "0")
      | Sil.Float_lit float ->
          bind_operand value (Printf.sprintf "0x%016LX" (Int64.bits_of_float float))
      | Sil.String_lit text -> bind_operand value (add_string_const text)
      | Sil.Alloc_stack _ -> () (* emitted in the entry block by gen_allocas below *)
      | Sil.Load address ->
          let result_operand = fresh_temp () in
          emit
            (Printf.sprintf "  %s = load %s, ptr %s\n" result_operand
               (llvm_type (value_type value)) (lookup_operand address));
          bind_operand value result_operand
      | Sil.Store (stored_value, address) ->
          emit
            (Printf.sprintf "  store %s %s, ptr %s\n"
               (llvm_type (value_type stored_value)) (lookup_operand stored_value)
               (lookup_operand address))
      | Sil.Binop (operator, left, right) -> gen_binop value operator left right
      | Sil.Unop (Ast.Neg, operand) ->
          let result_operand = fresh_temp () in
          if value_type operand = Types.TDouble then
            emit
              (Printf.sprintf "  %s = fneg double %s\n" result_operand
                 (lookup_operand operand))
          else
            emit
              (Printf.sprintf "  %s = sub i64 0, %s\n" result_operand
                 (lookup_operand operand));
          bind_operand value result_operand
      | Sil.Func_ref name -> bind_operand value ("@" ^ name)
      | Sil.Apply (function_operand, arguments) ->
          let argument_list =
            String.concat ", "
              (List.map
                 (fun argument ->
                   Printf.sprintf "%s %s" (llvm_type (value_type argument))
                     (lookup_operand argument))
                 arguments)
          in
          let return_type = value_type value in
          if return_type = Types.TVoid then
            emit
              (Printf.sprintf "  call void %s(%s)\n" (lookup_operand function_operand)
                 argument_list)
          else (
            let result_operand = fresh_temp () in
            emit
              (Printf.sprintf "  %s = call %s %s(%s)\n" result_operand
                 (llvm_type return_type) (lookup_operand function_operand) argument_list);
            bind_operand value result_operand)
      | Sil.Print printed_value -> gen_print printed_value
      (* structs — concept 10 *)
      | Sil.Struct _ | Sil.Struct_extract _ | Sil.Struct_element_addr _ ->
          (* TODO(10i): the three struct instructions — build an aggregate, read a field out of a
             VALUE, take the address of a field in a SLOT. §2 gives the LLVM for each. *)
          ignore (value, instruction);
          failwith "TODO(10i): lower the struct instruction (insertvalue/extractvalue/getelementptr)"
    in
    let gen_term (terminator : Sil.term) =
      match terminator with
      | Sil.Br target -> emit (Printf.sprintf "  br label %%bb%d\n" target)
      | Sil.Cond_br (condition, then_block, else_block) ->
          emit
            (Printf.sprintf "  br i1 %s, label %%bb%d, label %%bb%d\n"
               (lookup_operand condition) then_block else_block)
      | Sil.Return None -> emit (if is_main then "  ret i32 0\n" else "  ret void\n")
      | Sil.Return (Some return_value) ->
          emit
            (Printf.sprintf "  ret %s %s\n" (llvm_type function_definition.Sil.ret)
               (lookup_operand return_value))
      | Sil.Unreachable -> emit "  unreachable\n"
    in
    (* every alloca goes at the top of the ENTRY block: alloca'd stack space is only returned
       when the function exits, so an alloca inside a loop body would grow the stack every
       iteration. clang hoists allocas the same way (and LLVM's mem2reg only promotes
       entry-block allocas). *)
    let gen_allocas () =
      List.iter
        (fun (block : Sil.block) ->
          List.iter
            (fun (value, instruction) ->
              match (instruction : Sil.instr) with
              | Sil.Alloc_stack _ ->
                  let stack_operand = fresh_temp () in
                  emit
                    (Printf.sprintf "  %s = alloca %s\n" stack_operand
                       (llvm_type (value_type value)));
                  bind_operand value stack_operand
              | _ -> ())
            (List.rev block.Sil.instrs))
        (List.rev function_definition.Sil.blocks)
    in
    List.iteri
      (fun block_index (block : Sil.block) ->
        emit (Printf.sprintf "bb%d:\n" block.Sil.bid);
        if block_index = 0 then gen_allocas ();
        List.iter gen_instruction (List.rev block.Sil.instrs);
        gen_term block.Sil.term)
      (List.rev function_definition.Sil.blocks);
    emit "}\n\n"
  in
  List.iter gen_function sil_module.Sil.funcs;
  (* LLVM named type for each struct: `%Point = type { i64, i64 }` (concept 10) *)
  let struct_definitions =
    List.map
      (fun (layout : Types.struct_layout) ->
        Printf.sprintf "%%%s = type { %s }" layout.Types.sl_name
          (String.concat ", "
             (List.map (fun (_, field_type) -> llvm_type field_type) layout.Types.sl_fields)))
      sil_module.Sil.structs
  in
  (* assemble: preamble + struct types + string constants + functions *)
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
  preamble
  ^ (if struct_definitions = [] then "" else String.concat "\n" struct_definitions ^ "\n")
  ^ Buffer.contents global_definitions ^ "\n" ^ Buffer.contents function_definitions
