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

(* --regalloc <stack|linscan|graphcolor> picks the register-allocation rung (concept 34) *)
let regalloc_of args =
  let pick = List.find_map (fun a ->
      match String.split_on_char '=' a with
      | [ "--regalloc"; s ] -> Some s
      | _ -> None) args in
  match pick with
  | Some "stack" -> Regalloc.Stack
  | Some "linscan" -> Regalloc.Linscan
  | Some ("graphcolor" | "graph") | None -> Regalloc.Graphcolor
  | Some other -> prerr_endline ("unknown --regalloc " ^ other); exit 2

let () =
  let args = Array.to_list Sys.argv in
  let opt = List.mem "-O" args in
  let native = List.mem "--native" args in
  let peephole = not (List.mem "--no-peephole" args) in
  let regalloc = regalloc_of args in
  let args = List.filter (fun a ->
      a <> "-O" && a <> "--native" && a <> "--no-peephole" && not (String.length a > 11 && String.sub a 0 11 = "--regalloc=")) args in
  match args with
  | _ :: "build" :: file :: rest ->
      let out =
        match rest with
        | [] -> Filename.remove_extension (Filename.basename file)
        | [ "-o"; o ] -> o
        | _ -> usage ()
      in
      Driver.compile_file ~out ~opt ~native ~regalloc ~peephole ~src_path:file ~emit:Driver.Exe ()
  | _ :: flag :: [ file ] when emit_of_flag flag <> None ->
      Driver.compile_file ~opt ~regalloc ~peephole ~src_path:file ~emit:(Option.get (emit_of_flag flag)) ()
  | _ -> usage ()
