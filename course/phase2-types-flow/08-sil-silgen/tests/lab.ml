(* The concept `lab` CLI — linked against THIS concept's library, so the cram tests in this
   directory exercise YOUR code here (the phase binary links the phase's FINAL concept and would
   not see your work in this directory):
     ./lab.exe --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-sil-canon <file.swift>

   `--emit-sil-canon` prints the SIL in CANONICAL form — see `canon` below. The control-flow
   tests compare against it, because two lowerings can build the same graph and still print
   differently, and the difference is not something this concept asks you to get right. *)

let usage () =
  prerr_endline
    "usage: lab --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-sil-canon <file.swift>";
  exit 2

let emit_of_flag : string -> Driver.emit option = function
  | "--emit-tokens" -> Some Driver.Tokens
  | "--emit-ast" -> Some Driver.Ast
  | "--typecheck" -> Some Driver.Check
  | "--emit-sil" -> Some Driver.Sil
  | _ -> None

let emit_sil_canon (src_path : string) : unit =
  let src = Driver.read_file src_path in
  let diags = Diagnostics.create () in
  let prog = Driver.frontend src diags in
  Driver.bail_on_errors diags;
  print_string (Sil.string_of_module (Canon.canon (Silgen.lower prog)))

let () =
  match Array.to_list Sys.argv with
  | _ :: "--emit-sil-canon" :: [ file ] -> emit_sil_canon file
  | _ :: flag :: [ file ] when emit_of_flag flag <> None ->
      Driver.compile_file ~src_path:file ~emit:(Option.get (emit_of_flag flag))
  | _ -> usage ()
