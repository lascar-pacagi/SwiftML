(* The driver (given). Full pipeline: lex -> parse -> sema -> SILGen -> SIL -> [optimizer]
   -> IRGen -> LLVM -> clang -> native. `-O` = SIL passes + clang -O2 (concept 20). *)

type emit =
  | Tokens
  | Ast
  | Check
  | Sil (* raw SIL (no optimization) *)
  | Sil_opt (* optimized SIL (`--sil-opt`) *)
  | Llvm (* + IRGen, print LLVM IR (optimized if -O) *)
  | Exe (* + clang: a native executable (optimized if -O) *)

let read_file (path : string) : string =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () -> really_input_string ic (in_channel_length ic))

let frontend (src : string) (diags : Diagnostics.sink) : Ast.program =
  let toks = Lexer.tokenize (Lexer.create src) in
  let prog = Parser.parse_program (Parser.create toks diags) in
  Sema.check prog diags;
  prog

let bail_on_errors (diags : Diagnostics.sink) : unit =
  if Diagnostics.has_errors diags then (
    Diagnostics.print diags;
    exit 1)

(* source -> verified SIL (optimized if [opt]) *)
let lower_sil ?(opt = false) (src : string) (diags : Diagnostics.sink) : Sil.modul =
  let prog = frontend src diags in
  bail_on_errors diags;
  let m = Silgen.lower prog in
  (match Sil.verify m with
  | [] -> ()
  | errs ->
      List.iter (fun e -> prerr_endline ("SIL verification error: " ^ e)) errs;
      exit 1);
  if opt then Opt.optimize m else m

let run_clang ~(opt : bool) ~(ll_path : string) ~(out : string) : unit =
  (* concept 20: `-O` also engages LLVM's optimizer — clang runs the full -O2 pass pipeline
     (instcombine, GVN, LICM, SCEV/indvars, vectorizer, …) and an optimizing backend (isel,
     register allocation, scheduling) on the IR we emit. `-Onone` compiles at -O0: fast, naive. *)
  let oflag = if opt then "-O2" else "-O0" in
  let cmd = Printf.sprintf "clang %s -Wno-override-module %s -o %s" oflag (Filename.quote ll_path) (Filename.quote out) in
  if Sys.command cmd <> 0 then failwith (Printf.sprintf "clang failed on %s" ll_path)

let compile_file ?(out = "a.out") ?(opt = false) ~(src_path : string) ~(emit : emit) () : unit =
  let src = read_file src_path in
  let diags = Diagnostics.create () in
  match emit with
  | Tokens ->
      Lexer.tokenize (Lexer.create src)
      |> List.iter (fun (t : Token.t) -> print_endline (Token.string_of_kind t.Token.kind))
  | Ast ->
      let prog = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) diags) in
      bail_on_errors diags;
      print_endline (Ast.dump_program prog)
  | Check ->
      let (_ : Ast.program) = frontend src diags in
      bail_on_errors diags
  | Sil -> print_endline (Sil.string_of_module (lower_sil ~opt:false src diags))
  | Sil_opt -> print_endline (Sil.string_of_module (lower_sil ~opt:true src diags))
  | Llvm -> print_string (Irgen.emit_llvm (lower_sil ~opt src diags))
  | Exe ->
      let ll = Irgen.emit_llvm (lower_sil ~opt src diags) in
      let ll_path = Filename.temp_file "swiftml4" ".ll" in
      Fun.protect
        ~finally:(fun () -> try Sys.remove ll_path with _ -> ())
        (fun () ->
          let oc = open_out ll_path in
          output_string oc ll;
          close_out oc;
          run_clang ~opt ~ll_path ~out)
