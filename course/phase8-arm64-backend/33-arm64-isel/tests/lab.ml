(* The `lab` CLI — Phase 8 (the from-scratch ARM64 backend). Backend A (LLVM) stays; Backend B
   (native ARM64) arrives:
     lab build <file.swift> [-O] [--native] [-o <out>]   (--native = Backend B: our ARM64)
     lab --emit-asm <file.swift>                         (ARM64 assembly text)
     lab --emit-sil|--sil-opt|--emit-llvm [-O] <file.swift>
     lab --emit-tokens|--emit-ast|--typecheck <file.swift> *)

let usage () =
  prerr_endline "usage: lab build <file.swift> [-O] [--native] [-o <out>]";
  prerr_endline "       lab --emit-asm <file.swift>";
  prerr_endline "       lab --emit-sil|--sil-opt|--emit-llvm [-O] <file.swift>";
  prerr_endline "       lab --emit-tokens|--emit-ast|--typecheck <file.swift>";
  exit 2

let emit_of_flag : string -> Driver.emit option = function
  | "--emit-tokens" -> Some Driver.Tokens
  | "--emit-ast" -> Some Driver.Ast
  | "--typecheck" -> Some Driver.Check
  | "--emit-sil" -> Some Driver.Sil
  | "--sil-opt" -> Some Driver.Sil_opt
  | "--emit-llvm" -> Some Driver.Llvm
  | "--emit-asm" -> Some Driver.Asm
  | _ -> None

let () =
  let args = Array.to_list Sys.argv in
  let opt = List.mem "-O" args in
  let native = List.mem "--native" args in
  let args = List.filter (fun a -> a <> "-O" && a <> "--native") args in
  match args with
  | _ :: "build" :: file :: rest ->
      let out =
        match rest with
        | [] -> Filename.remove_extension (Filename.basename file)
        | [ "-o"; o ] -> o
        | _ -> usage ()
      in
      Driver.compile_file ~out ~opt ~native ~src_path:file ~emit:Driver.Exe ()
  | _ :: flag :: [ file ] when emit_of_flag flag <> None ->
      Driver.compile_file ~opt ~src_path:file ~emit:(Option.get (emit_of_flag flag)) ()
  | _ -> usage ()
