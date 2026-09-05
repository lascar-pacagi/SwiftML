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
  let toks = Lexer.tokenize (Lexer.create src diags) in
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
  (* concept 27: the OWNERSHIP verifier — ARC discipline checked statically, every compile *)
  (match Sil.verify_ownership m with
  | [] -> ()
  | errs ->
      List.iter (fun e -> prerr_endline ("ownership error: " ^ e)) errs;
      exit 1);
  if not opt then m
  else
    (* the pipeline runs, then the SAME verifier runs again: a pass that produced a malformed CFG
       (a branch to a block that does not exist, an argument list of the wrong length, a block with
       no terminator) is caught here rather than in IRGen or, worse, at run time *)
    let m = Opt.optimize m in
    match Sil.verify m with
    | [] -> m
    | errs ->
        List.iter (fun e -> prerr_endline ("SIL verification error after optimization: " ^ e)) errs;
        exit 1

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
      let toks = Lexer.tokenize (Lexer.create src diags) in
      bail_on_errors diags;
      List.iter (fun (t : Token.t) -> print_endline (Token.string_of_kind t.Token.kind)) toks
  | Ast ->
      let prog = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src diags)) diags) in
      bail_on_errors diags;
      print_endline (Ast.dump_program prog)
  | Check ->
      let (_ : Ast.program) = frontend src diags in
      (* print warnings too (concept 23's always-fails cast warns like swiftc); errors exit 1 *)
      Diagnostics.print diags;
      if Diagnostics.has_errors diags then exit 1
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
