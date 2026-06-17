(* The `swiftml2` CLI — Phase 2. By concept 09 the full pipeline runs:
     swiftml2 build <file.swift> [-o <out>]    compile to a native executable
     swiftml2 --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-llvm <file.swift>

   Modules come from the latest concept's stage library (wrapped false -> unqualified). *)

let usage () =
  prerr_endline "usage: swiftml2 build <file.swift> [-o <out>]";
  prerr_endline
    "       swiftml2 --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-llvm <file.swift>";
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
