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
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

(* Front end: source -> checked AST. Reports diagnostics into [diags]. *)
let frontend (src : string) (diags : Diagnostics.sink) : Ast.program =
  let toks = Lexer.tokenize (Lexer.create src diags) in
  let prog = Parser.parse_program (Parser.create toks diags) in
  Sema.check prog diags;
  prog

(* Assemble + link an LLVM IR file into a native executable with clang.
   clang recognizes the .ll extension and runs the LLVM backend + linker. *)
let run_clang ~(ll_path : string) ~(out : string) : unit =
  (* -Wno-override-module: our IR omits an explicit target triple on purpose (it's
     portable); clang fills in the host triple and would otherwise warn. *)
  let cmd =
    Printf.sprintf "clang -Wno-override-module %s -o %s" (Filename.quote ll_path)
      (Filename.quote out)
  in
  let rc = Sys.command cmd in
  if rc <> 0 then failwith (Printf.sprintf "clang failed (exit %d) on %s" rc ll_path)

let bail_on_errors (diags : Diagnostics.sink) : unit =
  if Diagnostics.has_errors diags then (
    Diagnostics.print diags;
    exit 1)

(* Compile one source file according to [emit]. *)
let compile_file ~(src_path : string) ~(out : string) ~(emit : emit) : unit =
  let src = read_file src_path in
  let diags = Diagnostics.create () in
  match emit with
  | Tokens ->
      let toks = Lexer.tokenize (Lexer.create src diags) in
      bail_on_errors diags;
      List.iter (fun (t : Token.t) -> print_endline (Token.string_of_kind t.Token.kind)) toks
  | Ast ->
      let prog = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src diags)) diags) in
      bail_on_errors diags;
      print_endline (Ast.dump_program prog)
  | Check ->
      (* Run the whole front end (lex → parse → sema) and report diagnostics, but stop
         before codegen. Lets us test Sema in isolation, exactly like `swiftc -typecheck`. *)
      let (_ : Ast.program) = frontend src diags in
      bail_on_errors diags
  | Llvm ->
      let prog = frontend src diags in
      bail_on_errors diags;
      print_string (Irgen.emit_llvm prog)
  | Exe ->
      let prog = frontend src diags in
      bail_on_errors diags;
      let ll = Irgen.emit_llvm prog in
      let ll_path = Filename.temp_file "swiftml" ".ll" in
      Fun.protect
        ~finally:(fun () -> (try Sys.remove ll_path with _ -> ()))
        (fun () ->
          let oc = open_out ll_path in
          output_string oc ll;
          close_out oc;
          run_clang ~ll_path ~out)
  | Sil -> failwith "TODO(Phase 2): --emit-sil (SILGen is introduced in phase2)"
  | Asm -> failwith "TODO(Phase 8): --emit-asm (the native ARM64 backend)"
