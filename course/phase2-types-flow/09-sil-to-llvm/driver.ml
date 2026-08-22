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
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () -> really_input_string ic (in_channel_length ic))

let frontend (src : string) (diags : Diagnostics.sink) : Ast.program =
  let toks = Lexer.tokenize (Lexer.create src diags) in
  let prog = Parser.parse_program (Parser.create toks diags) in
  Sema.check prog diags;
  prog

let bail_on_errors (diags : Diagnostics.sink) : unit =
  if Diagnostics.has_errors diags then (
    Diagnostics.print diags;
    exit 1)

(* source -> verified SIL -> LLVM IR text *)
let to_llvm (src : string) (diags : Diagnostics.sink) : string =
  let prog = frontend src diags in
  bail_on_errors diags;
  let m = Silgen.lower prog in
  (match Sil.verify m with
  | [] -> ()
  | errs ->
      List.iter (fun e -> prerr_endline ("SIL verification error: " ^ e)) errs;
      exit 1);
  Irgen.emit_llvm m

let run_clang ~(ll_path : string) ~(out : string) : unit =
  let cmd = Printf.sprintf "clang -Wno-override-module %s -o %s" (Filename.quote ll_path) (Filename.quote out) in
  if Sys.command cmd <> 0 then failwith (Printf.sprintf "clang failed on %s" ll_path)

let compile_file ?(out = "a.out") ~(src_path : string) ~(emit : emit) () : unit =
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
      let (_ : Ast.program) = frontend src diags in
      bail_on_errors diags
  | Sil ->
      let prog = frontend src diags in
      bail_on_errors diags;
      let m = Silgen.lower prog in
      bail_on_errors diags;
      print_endline (Sil.string_of_module m)
  | Llvm -> print_string (to_llvm src diags)
  | Exe ->
      let ll = to_llvm src diags in
      let ll_path = Filename.temp_file "swiftml2" ".ll" in
      Fun.protect
        ~finally:(fun () -> try Sys.remove ll_path with _ -> ())
        (fun () ->
          let oc = open_out ll_path in
          output_string oc ll;
          close_out oc;
          run_clang ~ll_path ~out)
