(* The `swiftml3` CLI — Phase 3 (value types). Same surface as `swiftml2`, on the compiler
   extended with structs/enums/...:
     swiftml3 build <file.swift> [-o <out>]
     swiftml3 --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-layout|--emit-llvm <file.swift> *)

let usage () =
  prerr_endline "usage: swiftml3 build <file.swift> [-o <out>]";
  prerr_endline
    "       swiftml3 --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-layout|--emit-llvm <file.swift>";
  exit 2

let emit_of_flag : string -> Driver.emit option = function
  | "--emit-tokens" -> Some Driver.Tokens
  | "--emit-ast" -> Some Driver.Ast
  | "--typecheck" -> Some Driver.Check
  | "--emit-sil" -> Some Driver.Sil
  | "--emit-layout" -> Some Driver.Layout
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
