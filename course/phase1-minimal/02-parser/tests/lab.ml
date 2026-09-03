(* The concept `lab` CLI — linked against THIS concept's library, so the cram tests in this
   directory exercise YOUR parser.ml. Three seams, one per hole, so each can go green alone:
     ./lab.exe --emit-expr <file>   parse the file as ONE expression   (TODO(02a))
     ./lab.exe --emit-stmt <file>   parse the file as ONE statement    (TODO(02b), needs 02a)
     ./lab.exe --emit-ast  <file>   the whole program, like swiftml    (TODO(02c), needs both)
   Diagnostics go to stderr as `line:col: error: …` and the exit code is 1, like the driver. *)

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
  | [ _; mode; file ] when mode = "--emit-expr" || mode = "--emit-stmt" || mode = "--emit-ast" ->
      let diags = Diagnostics.create () in
      let toks = Lexer.tokenize (Lexer.create (read_file file) diags) in
      bail diags;
      let p = Parser.create toks diags in
      let out =
        match mode with
        | "--emit-expr" -> Ast.dump_expr (Parser.parse_expr p)
        | "--emit-stmt" -> Ast.dump_stmt (Parser.parse_stmt p)
        | _ -> Ast.dump_program (Parser.parse_program p)
      in
      bail diags;
      print_endline out
  | _ ->
      prerr_endline "usage: lab --emit-expr|--emit-stmt|--emit-ast <file.swift>";
      exit 2
