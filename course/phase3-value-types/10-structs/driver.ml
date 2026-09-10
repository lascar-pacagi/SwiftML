(* The driver — a *contract* (given). The full Phase-2 pipeline:
   lex -> parse -> sema -> SILGen -> SIL -> IRGen -> LLVM IR -> clang -> native.
   Concept 09 adds `--emit-llvm` and `build` (programs finally run). *)

type emit =
  | Tokens
  | Ast
  | Check
  | Sil
  | Llvm (* + IRGen, print LLVM IR *)
  | Exe (* + clang: a native executable *)

let read_file (path : string) : string =
  let input_channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in input_channel) (fun () -> really_input_string input_channel (in_channel_length input_channel))

let frontend (source : string) (diagnostics : Diagnostics.sink) : Ast.program =
  let tokens = Lexer.tokenize (Lexer.create source diagnostics) in
  let program = Parser.parse_program (Parser.create tokens diagnostics) in
  Sema.check program diagnostics;
  program

let bail_on_errors (diagnostics : Diagnostics.sink) : unit =
  if Diagnostics.has_errors diagnostics then (
    Diagnostics.print diagnostics;
    exit 1)

(* source -> verified SIL -> LLVM IR text *)
let to_llvm (source : string) (diagnostics : Diagnostics.sink) : string =
  let program = frontend source diagnostics in
  bail_on_errors diagnostics;
  let sil_module = Silgen.lower program in
  (match Sil.verify sil_module with
  | [] -> ()
  | errors ->
      List.iter (fun error_message -> prerr_endline ("SIL verification error: " ^ error_message)) errors;
      exit 1);
  Irgen.emit_llvm sil_module

let run_clang ~(ll_path : string) ~(out : string) : unit =
  let command = Printf.sprintf "clang -Wno-override-module %s -o %s" (Filename.quote ll_path) (Filename.quote out) in
  if Sys.command command <> 0 then failwith (Printf.sprintf "clang failed on %s" ll_path)

let compile_file ?(out = "a.out") ~(src_path : string) ~(emit : emit) () : unit =
  let source = read_file src_path in
  let diagnostics = Diagnostics.create () in
  match emit with
  | Tokens ->
      let tokens = Lexer.tokenize (Lexer.create source diagnostics) in
      bail_on_errors diagnostics;
      List.iter (fun (token : Token.t) -> print_endline (Token.string_of_kind token.Token.kind)) tokens
  | Ast ->
      let program = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create source diagnostics)) diagnostics) in
      bail_on_errors diagnostics;
      print_endline (Ast.dump_program program)
  | Check ->
      let (_ : Ast.program) = frontend source diagnostics in
      bail_on_errors diagnostics
  | Sil ->
      let program = frontend source diagnostics in
      bail_on_errors diagnostics;
      let sil_module = Silgen.lower program in
      bail_on_errors diagnostics;
      print_endline (Sil.string_of_module sil_module)
  | Llvm -> print_string (to_llvm source diagnostics)
  | Exe ->
      let llvm_ir = to_llvm source diagnostics in
      let ll_path = Filename.temp_file "swiftml2" ".ll" in
      Fun.protect
        ~finally:(fun () -> try Sys.remove ll_path with _ -> ())
        (fun () ->
          let output_channel = open_out ll_path in
          output_string output_channel llvm_ir;
          close_out output_channel;
          run_clang ~ll_path ~out)
