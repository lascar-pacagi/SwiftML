(* The concept `lab` CLI — linked against THIS concept's library, so the cram tests in this
   directory exercise YOUR code here (the phase binary links the phase's FINAL concept and would
   not see your work in this directory):
     ./lab.exe --emit-tokens|--emit-ast|--emit-params|--emit-returns|--typecheck <file.swift>

   Two of those modes exist so a hole can report on its own rather than waiting for the one after
   it. `--emit-params` parses ONE parameter list and stops, reaching `parse_params` directly
   instead of through `parse_func`. `--emit-returns` parses a program and asks `Sema.block_returns`
   about each function's body, without running `check` — so the definite-return analysis is
   graded on its own, before the two-pass driver exists. *)

let usage () =
  prerr_endline
    "usage: lab \
     --emit-tokens|--emit-ast|--emit-params|--emit-returns|--typecheck \
     <file.swift>";
  exit 2

let emit_of_flag : string -> Driver.emit option = function
  | "--emit-tokens" -> Some Driver.Tokens
  | "--emit-ast" -> Some Driver.Ast
  | "--typecheck" -> Some Driver.Check
  | _ -> None

(* lex, then `parse_params` on the whole file: the source IS a parameter list, `(a: Int, …)`.
   Prints it the way `--emit-ast` prints the list inside a func — via `Ast.dump_param`, so the
   two tests agree character for character. *)
let emit_params (src_path : string) : unit =
  let src = Driver.read_file src_path in
  let diags = Diagnostics.create () in
  let toks = Lexer.tokenize (Lexer.create src diags) in
  let params = Parser.parse_params (Parser.create toks diags) in
  Driver.bail_on_errors diags;
  print_endline
    (Printf.sprintf "(%s)" (String.concat " " (List.map Ast.dump_param params)))

(* For each function in the file: does its body definitely return on every path? Parses, then
   calls `Sema.block_returns` directly — `Sema.check` never runs, so this reports on the analysis
   and nothing else. *)
let emit_returns (src_path : string) : unit =
  let src = Driver.read_file src_path in
  let diags = Diagnostics.create () in
  let prog =
    Parser.parse_program
      (Parser.create (Lexer.tokenize (Lexer.create src diags)) diags)
  in
  Driver.bail_on_errors diags;
  List.iter
    (function
      | Ast.IFunc f ->
          Printf.printf "%s: %s\n" f.Ast.fname
            (if Sema.block_returns f.Ast.body then "returns"
             else "does not return")
      | Ast.IStmt _ -> ())
    prog.Ast.items

let () =
  match Array.to_list Sys.argv with
  | _ :: "--emit-params" :: [ file ] -> emit_params file
  | _ :: "--emit-returns" :: [ file ] -> emit_returns file
  | _ :: flag :: [ file ] when emit_of_flag flag <> None ->
      Driver.compile_file ~src_path:file ~emit:(Option.get (emit_of_flag flag))
  | _ -> usage ()
