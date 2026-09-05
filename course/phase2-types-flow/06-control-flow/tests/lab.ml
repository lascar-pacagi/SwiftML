(* The concept `lab` CLI — linked against THIS concept's library, so the cram tests in this
   directory exercise YOUR code here (the phase binary links the phase's FINAL concept and would
   not see your work in this directory):

     ./lab.exe --emit-tokens <file>   the token stream            (the lexer hole)
     ./lab.exe --emit-block  <file>   parse the file as ONE block (parse_block, on its own)
     ./lab.exe --emit-ast    <file>   the whole program           (needs parse_stmt's new arms)
     ./lab.exe --typecheck   <file>   lex → parse → sema          (the sema holes)

   `--emit-block` exists so `parse_block` can be finished and tested before `parse_if` and the
   loop statements are written: the file it reads IS a block, braces and all. *)

let usage () =
  prerr_endline "usage: lab --emit-tokens|--emit-block|--emit-ast|--typecheck <file.swift>";
  exit 2

let emit_of_flag : string -> Driver.emit option = function
  | "--emit-tokens" -> Some Driver.Tokens
  | "--emit-ast" -> Some Driver.Ast
  | "--typecheck" -> Some Driver.Check
  | _ -> None

let read_file (path : string) : string =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
      really_input_string ic (in_channel_length ic))

(* parse the file as a single block and print it, so the report is about parse_block alone *)
let emit_block (file : string) : unit =
  let diags = Diagnostics.create () in
  let toks = Lexer.tokenize (Lexer.create (read_file file) diags) in
  let bail () = if Diagnostics.has_errors diags then (Diagnostics.print diags; exit 1) in
  bail ();
  let p = Parser.create toks diags in
  let stmts = Parser.parse_block p in
  bail ();
  print_endline (Ast.dump_block stmts)

let () =
  match Array.to_list Sys.argv with
  | [ _; "--emit-block"; file ] -> emit_block file
  | _ :: flag :: [ file ] when emit_of_flag flag <> None ->
      Driver.compile_file ~src_path:file ~emit:(Option.get (emit_of_flag flag))
  | _ -> usage ()
