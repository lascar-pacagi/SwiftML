(* The concept `lab` CLI — linked against THIS concept's library, so the cram tests in this
   directory exercise YOUR code here (the phase binary links the phase's FINAL concept and would
   not see your work in this directory):
     ./lab.exe --emit-tokens|--emit-ast|--typecheck|--emit-tast|--emit-sil|--emit-sil-canon <file.swift>

   `--emit-sil-canon` prints the SIL in CANONICAL form — see `canon` below. The control-flow
   tests compare against it, because two lowerings can build the same graph and still print
   differently, and the difference is not something this concept asks you to get right.

   WITH §6 EXERCISES 2 AND 3 APPLIED: `--roundtrip-sil file.sil` and
   `--split-critical-edges file.swift`. *)

let usage () =
  prerr_endline
    "usage: lab \
     --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-sil-canon \
     <file.swift>";
  exit 2

let emit_of_flag : string -> Driver.emit option = function
  | "--emit-tokens" -> Some Driver.Tokens
  | "--emit-ast" -> Some Driver.Ast
  | "--typecheck" -> Some Driver.Check
  | "--emit-tast" -> Some Driver.Typed_ast
  | "--emit-sil" -> Some Driver.Sil
  | _ -> None

let emit_sil_canon (src_path : string) : unit =
  let src = Driver.read_file src_path in
  let diags = Diagnostics.create ~source:src () in
  let prog = Driver.frontend src diags in
  Driver.bail_on_errors diags;
  print_string (Sil.string_of_module (Canon.canon (Silgen.lower (Option.get prog))))

(* EX2: read a .sil file back and print it again — the round trip that makes a `.sil` file
   a valid input, which Phase 4's single-pass testing relies on *)
let roundtrip_sil (sil_path : string) : unit =
  match Sil.of_string (Driver.read_file sil_path) with
  | m -> print_endline (Sil.string_of_module m)
  | exception Sil.Parse_error msg ->
      prerr_endline ("error: " ^ msg);
      exit 1

(* EX3: lower a program, split its critical edges, print the result *)
let split_critical_edges (src_path : string) : unit =
  let src = Driver.read_file src_path in
  let diags = Diagnostics.create ~source:src () in
  let prog = Driver.frontend src diags in
  Driver.bail_on_errors diags;
  print_endline
    (Sil.string_of_module (Sil.split_critical_edges (Silgen.lower (Option.get prog))))

let () =
  match Array.to_list Sys.argv with
  | _ :: "--emit-sil-canon" :: [ file ] -> emit_sil_canon file
  | _ :: "--roundtrip-sil" :: [ file ] -> roundtrip_sil file (* EX2 *)
  | _ :: "--split-critical-edges" :: [ file ] -> split_critical_edges file (* EX3 *)
  | _ :: flag :: [ file ] when emit_of_flag flag <> None ->
      Driver.compile_file ~src_path:file ~emit:(Option.get (emit_of_flag flag))
  | _ -> usage ()
