(* The `swiftml7` CLI — Phase 7 (closures & stdlib). Same surface as `swiftml3`, plus `-O` (run the
   SIL optimizer) and `--sil-opt` (print the optimized SIL):
     swiftml7 build <file.swift> [-O] [-o <out>]
     swiftml7 --emit-sil|--sil-opt|--emit-llvm [-O] <file.swift>
     swiftml7 --emit-tokens|--emit-ast|--typecheck <file.swift> *)

let usage () =
  prerr_endline "usage: swiftml7 build <file.swift> [-O] [-o <out>]";
  prerr_endline "       swiftml7 --emit-sil|--sil-opt|--emit-llvm [-O] <file.swift>";
  prerr_endline "       swiftml7 --emit-tokens|--emit-ast|--typecheck <file.swift>";
  exit 2

let emit_of_flag : string -> Driver.emit option = function
  | "--emit-tokens" -> Some Driver.Tokens
  | "--emit-ast" -> Some Driver.Ast
  | "--typecheck" -> Some Driver.Check
  | "--emit-sil" -> Some Driver.Sil
  | "--sil-opt" -> Some Driver.Sil_opt
  | "--emit-llvm" -> Some Driver.Llvm
  | _ -> None

let () =
  let args = Array.to_list Sys.argv in
  let opt = List.mem "-O" args in
  let args = List.filter (fun a -> a <> "-O") args in
  match args with
  | _ :: "build" :: file :: rest ->
      let out =
        match rest with
        | [] -> Filename.remove_extension (Filename.basename file)
        | [ "-o"; o ] -> o
        | _ -> usage ()
      in
      Driver.compile_file ~out ~opt ~src_path:file ~emit:Driver.Exe ()
  | _ :: flag :: [ file ] when emit_of_flag flag <> None ->
      Driver.compile_file ~opt ~src_path:file ~emit:(Option.get (emit_of_flag flag)) ()
  | _ -> usage ()
