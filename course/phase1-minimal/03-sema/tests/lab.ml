(* The concept `lab` CLI — linked against THIS concept's library, so the cram tests in this
   directory exercise YOUR sema.ml (the phase binary `swiftml` links the whole chain).
     ./lab.exe --typecheck <file>   lex → parse → sema, no codegen — like `swiftc -typecheck`
   Diagnostics go to stderr as `line:col: severity: …` in report order; exit 1 on any error,
   0 when the program is well-formed. Nothing is printed for a clean program. *)

let read_file (path : string) : string =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
      really_input_string ic (in_channel_length ic))

let bail (diags : Diagnostics.sink) : unit =
  if Diagnostics.has_errors diags then (
    Diagnostics.print diags;
    exit 1)

let () =
  match Array.to_list Sys.argv with
  | [ _; "--typecheck"; file ] ->
      let diags = Diagnostics.create () in
      let toks = Lexer.tokenize (Lexer.create (read_file file) diags) in
      bail diags;
      let prog = Parser.parse_program (Parser.create toks diags) in
      bail diags;
      Sema.check prog diags;
      bail diags
  | _ ->
      prerr_endline "usage: lab --typecheck <file.swift>";
      exit 2
