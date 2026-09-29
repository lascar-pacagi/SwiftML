(* The concept `lab` CLI — linked against THIS concept's library, so the cram tests in this
   directory exercise YOUR code here (the phase binary links the phase's FINAL concept and would
   not see your work in this directory):
     ./lab.exe build <file.swift> [-o <out>]
     ./lab.exe --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-llvm <file.swift>
     ./lab.exe --binop-table <Int|Double|Bool>  (binop_instruction alone, no program)
     ./lab.exe --emit-llvm-allocas <file.swift>  (test gen_allocas before the rest)
     ./lab.exe --emit-llvm-instrs <file.swift>  (test gen_instr before gen_term)
     ./lab.exe --emit-llvm-terms <kind> <file.swift>  (test one terminator kind) *)

let usage () =
  prerr_endline "usage: lab build <file.swift> [-o <out>]";
  prerr_endline
    "       lab --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-llvm \
     <file.swift>";
  prerr_endline "       lab --binop-table <Int|Double|Bool>";
  prerr_endline "       lab --emit-llvm-allocas <file.swift>";
  prerr_endline "       lab --emit-llvm-instrs <file.swift>";
  prerr_endline
    "       lab --emit-llvm-terms \
     <br|cond-br|return-value|return-none|unreachable> <file.swift>";
  exit 2

let emit_of_flag : string -> Driver.emit option = function
  | "--emit-tokens" -> Some Driver.Tokens
  | "--emit-ast" -> Some Driver.Ast
  | "--typecheck" -> Some Driver.Check
  | "--emit-tast" -> Some Driver.Typed_ast
  | "--emit-sil" -> Some Driver.Sil
  | "--emit-llvm" -> Some Driver.Llvm
  | _ -> None

let () =
  match Array.to_list Sys.argv with
  | _ :: "build" :: file :: rest ->
      let out =
        match rest with
        | [] -> Filename.remove_extension (Filename.basename file)
        | [ "-o"; o ] -> o
        | _ -> usage ()
      in
      Driver.compile_file ~out ~src_path:file ~emit:Driver.Exe ()
  | _ :: "--binop-table" :: [ type_name ] ->
      (* every operator that exists at this operand type, and the instruction it becomes *)
      let arithmetic = [ ("+", Ast.Add); ("-", Ast.Sub); ("*", Ast.Mul); ("/", Ast.Div) ] in
      let comparisons =
        [ ("==", Ast.Eq); ("!=", Ast.Ne); ("<", Ast.Lt); ("<=", Ast.Le); (">", Ast.Gt);
          (">=", Ast.Ge) ]
      in
      let operand_type, operators =
        match type_name with
        | "Int" -> (Types.TInt, arithmetic @ [ ("%", Ast.Mod) ] @ comparisons)
        | "Double" -> (Types.TDouble, arithmetic @ comparisons)
        | "Bool" -> (Types.TBool, [ ("==", Ast.Eq); ("!=", Ast.Ne) ])
        | _ -> usage ()
      in
      List.iter
        (fun (symbol, operator) ->
          Printf.printf "%-3s %s\n" symbol (Irgen.binop_instruction operator operand_type))
        operators
  | _ :: "--emit-llvm-allocas" :: [ file ] ->
      (* only what gen_allocas writes: every instruction but alloc_stack is dropped from the
         SIL and no terminator is printed, so neither gen_instr nor gen_term is reached *)
      let source = Driver.read_file file in
      let diagnostics = Diagnostics.create ~source () in
      let program = Driver.frontend source diagnostics in
      Driver.bail_on_errors diagnostics;
      let sil_module = Silgen.lower (Option.get program) in
      let is_alloc_stack = function _, Sil.Alloc_stack _ -> true | _ -> false in
      List.iter
        (fun (func : Sil.func) ->
          List.iter
            (fun (block : Sil.block) ->
              block.Sil.instrs <- List.filter is_alloc_stack block.Sil.instrs)
            func.Sil.blocks)
        sil_module.Sil.funcs;
      print_string
        (Irgen.emit_llvm ~should_emit_terminator:(fun _ -> false) sil_module)
  | _ :: "--emit-llvm-instrs" :: [ file ] ->
      let source = Driver.read_file file in
      let diagnostics = Diagnostics.create ~source () in
      print_string
        (Driver.to_llvm
           ~should_emit_terminator:(fun _ -> false)
           source diagnostics)
  | _ :: "--emit-llvm-terms" :: kind :: [ file ] ->
      let should_emit_terminator =
        match kind with
        | "br" -> ( function Sil.Br _ -> true | _ -> false)
        | "cond-br" -> ( function Sil.Cond_br _ -> true | _ -> false)
        | "return-value" -> (
            function Sil.Return (Some _) -> true | _ -> false)
        | "return-none" -> ( function Sil.Return None -> true | _ -> false)
        | "unreachable" -> ( function Sil.Unreachable -> true | _ -> false)
        | _ -> usage ()
      in
      let source = Driver.read_file file in
      let diagnostics = Diagnostics.create ~source () in
      print_string (Driver.to_llvm ~should_emit_terminator source diagnostics)
  | _ :: flag :: [ file ] when emit_of_flag flag <> None ->
      Driver.compile_file ~src_path:file
        ~emit:(Option.get (emit_of_flag flag))
        ()
  | _ -> usage ()
