(* The concept `lab` CLI — linked against THIS concept's library, so the cram tests in this
   directory exercise YOUR code here (the phase binary links the phase's FINAL concept and would
   not see your work in this directory):
     ./lab.exe --emit-tokens|--emit-ast|--emit-params|--typecheck <file.swift>

   `--emit-params` parses ONE parameter list and stops. It exists so tests/parser-params.t can
   report on `parse_params` alone: the list is reached directly rather than through `parse_func`,
   so that hole goes green on its own instead of waiting for the one after it. *)

let usage () =
  prerr_endline "usage: lab --emit-tokens|--emit-ast|--emit-params|--typecheck <file.swift>";
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
  print_endline (Printf.sprintf "(%s)" (String.concat " " (List.map Ast.dump_param params)))

let () =
  match Array.to_list Sys.argv with
  | _ :: "--emit-params" :: [ file ] -> emit_params file
  | _ :: flag :: [ file ] when emit_of_flag flag <> None ->
      Driver.compile_file ~src_path:file ~emit:(Option.get (emit_of_flag flag))
  | _ -> usage ()
