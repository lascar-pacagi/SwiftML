(* The concept `lab` CLI — linked against THIS concept's library, so the cram tests in this
   directory exercise YOUR code here (the phase binary links the phase's FINAL concept and would
   not see your work in this directory):

     ./lab.exe --emit-tokens <file>   the token stream            (the lexer hole)
     ./lab.exe --emit-block  <file>   parse the file as ONE block     (parse_block, alone)
     ./lab.exe --emit-if     <file>   parse the file as ONE if-stmt   (parse_if, alone)
     ./lab.exe --emit-ast    <file>   the whole program               (parse_stmt's new arms)
     ./lab.exe --typecheck   <file>   lex → parse → sema              (the sema holes)

   `--emit-block` and `--emit-if` exist so each function can be finished and tested BEFORE the
   thing that normally calls it: the file they read is a block, or an if-statement, on its own.
   Once `parse_stmt` dispatches on the new keywords, `--emit-ast` reaches them all. *)

let usage () =
  prerr_endline
    "usage: lab --emit-tokens|--emit-block|--emit-if|--emit-ast|--typecheck \
     <file.swift>";
  exit 2

let emit_of_flag : string -> Driver.emit option = function
  | "--emit-tokens" -> Some Driver.Tokens
  | "--emit-ast" -> Some Driver.Ast
  | "--typecheck" -> Some Driver.Check
  | _ -> None

let read_file (path : string) : string =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

(* parse the file as ONE construct and print it, so the report is about that function alone *)
let emit_one (file : string) (parse : Parser.t -> string) : unit =
  let diags = Diagnostics.create () in
  let toks = Lexer.tokenize (Lexer.create (read_file file) diags) in
  let bail () =
    if Diagnostics.has_errors diags then (
      Diagnostics.print diags;
      exit 1)
  in
  bail ();
  let p = Parser.create toks diags in
  let out = parse p in
  bail ();
  print_endline out

let () =
  match Array.to_list Sys.argv with
  | [ _; "--emit-block"; file ] ->
      emit_one file (fun p -> Ast.dump_block (Parser.parse_block p))
  | [ _; "--emit-if"; file ] ->
      emit_one file (fun p -> Ast.dump_stmt (Parser.parse_if p))
  | _ :: flag :: [ file ] when emit_of_flag flag <> None ->
      Driver.compile_file ~src_path:file ~emit:(Option.get (emit_of_flag flag))
  | _ -> usage ()
