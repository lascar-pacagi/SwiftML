(* The driver — a *contract* (given). Ties the Phase-2 front end together. Concept 08 adds
   `--emit-sil` (lex -> parse -> sema -> SILGen -> verify -> print). Running the SIL is
   concept 09 (IRGen -> LLVM). Mirrors swift/lib/FrontendTool at small scale. *)

type emit =
  | Tokens
  | Ast
  | Check (* lex -> parse -> sema, then stop *)
  | Sil (* + SILGen, print the SIL module *)

let read_file (path : string) : string =
  let input_channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in input_channel)
    (fun () ->
      really_input_string input_channel (in_channel_length input_channel))

let frontend (source : string) (diagnostics : Diagnostics.sink) : Ast.program =
  let tokens = Lexer.tokenize (Lexer.create source diagnostics) in
  let program = Parser.parse_program (Parser.create tokens diagnostics) in
  Sema.check program diagnostics;
  program

let bail_on_errors (diagnostics : Diagnostics.sink) : unit =
  if Diagnostics.has_errors diagnostics then (
    Diagnostics.print diagnostics;
    exit 1)

let compile_file ~(src_path : string) ~(emit : emit) : unit =
  let source = read_file src_path in
  let diagnostics = Diagnostics.create () in
  match emit with
  | Tokens ->
      let tokens = Lexer.tokenize (Lexer.create source diagnostics) in
      bail_on_errors diagnostics;
      List.iter
        (fun (token : Token.t) ->
          print_endline (Token.string_of_kind token.Token.kind))
        tokens
  | Ast ->
      let program =
        Parser.parse_program
          (Parser.create
             (Lexer.tokenize (Lexer.create source diagnostics))
             diagnostics)
      in
      bail_on_errors diagnostics;
      print_endline (Ast.dump_program program)
  | Check ->
      let (_ : Ast.program) = frontend source diagnostics in
      bail_on_errors diagnostics
  | Sil ->
      let program = frontend source diagnostics in
      bail_on_errors diagnostics;
      let sil_module = Silgen.lower program in
      (match Sil.verify sil_module with
      | [] -> ()
      | errors ->
          List.iter
            (fun message ->
              prerr_endline ("SIL verification error: " ^ message))
            errors;
          exit 1);
      print_endline (Sil.string_of_module sil_module)
