(* The `swiftml` command-line front end (Phase 1).

   Usage:
     swiftml build <file.swift> [-o <out>]     compile to a native executable
     swiftml --emit-tokens <file.swift>         dump the lexer output  (concept 01)
     swiftml --emit-ast    <file.swift>         dump the parsed AST    (concept 02)
     swiftml --emit-sil    <file.swift>         dump SIL               (Phase 2+)
     swiftml --emit-llvm   <file.swift>         dump LLVM IR           (concept 04)
     swiftml --emit-asm    <file.swift>         dump native asm        (Phase 8)

   Modules come from the stage libraries (Driver is in swiftml_codegen, etc.); the
   libraries are `wrapped false`, so we refer to them unqualified. *)

let usage () =
  prerr_endline "usage: swiftml build <file.swift> [-o <out>]";
  prerr_endline
    "       swiftml --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-llvm|--emit-asm \
     <file.swift>";
  exit 2

let emit_of_flag : string -> Driver.emit option = function
  | "--emit-tokens" -> Some Driver.Tokens
  | "--emit-ast" -> Some Driver.Ast
  | "--typecheck" -> Some Driver.Check
  | "--emit-sil" -> Some Driver.Sil
  | "--emit-llvm" -> Some Driver.Llvm
  | "--emit-asm" -> Some Driver.Asm
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
      Driver.compile_file ~src_path:file ~out ~emit:Driver.Exe
  | _ :: flag :: [ file ] when emit_of_flag flag <> None ->
      Driver.compile_file ~src_path:file ~out:"/dev/null" ~emit:(Option.get (emit_of_flag flag))
  | _ -> usage ()
