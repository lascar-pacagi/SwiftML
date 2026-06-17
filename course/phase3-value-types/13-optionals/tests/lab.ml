(* The concept `lab` CLI — linked against THIS concept's library, so the cram tests in this
   directory exercise YOUR code here (the phase binary links the phase's FINAL concept and would
   not see your work in this directory):
     ./lab.exe build <file.swift> [-o <out>]
     ./lab.exe --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-llvm <file.swift> *)

let usage () =
  prerr_endline "usage: lab build <file.swift> [-o <out>]";
  prerr_endline "       lab --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-llvm <file.swift>";
  exit 2

let emit_of_flag : string -> Driver.emit option = function
  | "--emit-tokens" -> Some Driver.Tokens
  | "--emit-ast" -> Some Driver.Ast
  | "--typecheck" -> Some Driver.Check
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
  | _ :: flag :: [ file ] when emit_of_flag flag <> None ->
      Driver.compile_file ~src_path:file ~emit:(Option.get (emit_of_flag flag)) ()
  | _ -> usage ()
