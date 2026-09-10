(* The driver: tie the pipeline together and produce output.

   Mirrors swift/lib/Driver + swift/lib/FrontendTool (at a much smaller scale).
   The pipeline wiring below is *written for you*; the pieces it calls (Lexer.next,
   Parser.parse_program, Sema.check, Irgen.emit_llvm) are the skeletons you fill in
   across phase1-minimal/01..04. Once they work, `swiftml build foo.swift` produces a
   real native executable. *)

type emit =
  | Tokens
  | Ast
  | Check (* front end only: lex/parse/sema, like swiftc -typecheck; no codegen *)
  | Sil (* Phase 2+ *)
  | Llvm
  | Asm (* Phase 8 native backend *)
  | Exe

let read_file (path : string) : string =
  let input_channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in input_channel)
    (fun () -> really_input_string input_channel (in_channel_length input_channel))

(* Front end: source -> checked AST. Reports diagnostics into [diagnostics]. *)
let frontend (source : string) (diagnostics : Diagnostics.sink) : Ast.program =
  let tokens = Lexer.tokenize (Lexer.create source diagnostics) in
  let program = Parser.parse_program (Parser.create tokens diagnostics) in
  Sema.check program diagnostics;
  program

(* Assemble + link an LLVM IR file into a native executable with clang.
   clang recognizes the .ll extension and runs the LLVM backend + linker. *)
let run_clang ~(ll_path : string) ~(out : string) : unit =
  (* -Wno-override-module: our IR omits an explicit target triple on purpose (it's
     portable); clang fills in the host triple and would otherwise warn. *)
  let command =
    Printf.sprintf "clang -Wno-override-module %s -o %s" (Filename.quote ll_path)
      (Filename.quote out)
  in
  let exit_code = Sys.command command in
  if exit_code <> 0 then failwith (Printf.sprintf "clang failed (exit %d) on %s" exit_code ll_path)

let bail_on_errors (diagnostics : Diagnostics.sink) : unit =
  if Diagnostics.has_errors diagnostics then (
    Diagnostics.print diagnostics;
    exit 1)

(* Compile one source file according to [emit]. *)
let compile_file ~(src_path : string) ~(out : string) ~(emit : emit) : unit =
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
      (* Run the whole front end (lex → parse → sema) and report diagnostics, but stop
         before codegen. Lets us test Sema in isolation, exactly like `swiftc -typecheck`. *)
      let (_ : Ast.program) = frontend source diagnostics in
      bail_on_errors diagnostics
  | Llvm ->
      let program = frontend source diagnostics in
      bail_on_errors diagnostics;
      print_string (Irgen.emit_llvm program)
  | Exe ->
      let program = frontend source diagnostics in
      bail_on_errors diagnostics;
      let llvm_ir = Irgen.emit_llvm program in
      let ll_path = Filename.temp_file "swiftml" ".ll" in
      Fun.protect
        ~finally:(fun () -> (try Sys.remove ll_path with _ -> ()))
        (fun () ->
          let output_channel = open_out ll_path in
          output_string output_channel llvm_ir;
          close_out output_channel;
          run_clang ~ll_path ~out)
  | Sil -> failwith "TODO(Phase 2): --emit-sil (SILGen is introduced in phase2)"
  | Asm -> failwith "TODO(Phase 8): --emit-asm (the native ARM64 backend)"
