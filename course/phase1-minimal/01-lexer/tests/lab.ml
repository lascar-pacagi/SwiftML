(* The concept `lab` CLI — linked against THIS concept's library, so the cram tests in this
   directory exercise YOUR lexer.ml (the phase binary `swiftml` links every stage of Phase 1
   and would not isolate this one). Mirrors Driver's `--emit-tokens` exactly, so the goldens
   are the same stream `swiftml --emit-tokens` prints:
     ./lab.exe --emit-tokens <file.swift> *)

let read_file (path : string) : string =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
      really_input_string ic (in_channel_length ic))

let () =
  match Array.to_list Sys.argv with
  | [ _; "--emit-tokens"; file ] ->
      let diags = Diagnostics.create () in
      let toks = Lexer.tokenize (Lexer.create (read_file file) diags) in
      if Diagnostics.has_errors diags then (
        Diagnostics.print diags;
        exit 1);
      List.iter (fun (t : Token.t) -> print_endline (Token.string_of_kind t.Token.kind)) toks
  | _ ->
      prerr_endline "usage: lab --emit-tokens <file.swift>";
      exit 2
