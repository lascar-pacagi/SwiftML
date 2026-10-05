(* The concept `lab` CLI — linked against THIS concept's library, so the cram tests in this
   directory exercise YOUR code here (the phase binary links the phase's FINAL concept and would
   not see your work in this directory):
     ./lab.exe build <file.swift> [-o <out>]
     ./lab.exe --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-llvm <file.swift>
     ./lab.exe --emit-spans <file.swift>  (each top-level expression, and where it is) *)

let usage () =
  prerr_endline "usage: lab build <file.swift> [-o <out>]";
  prerr_endline "       lab --emit-spans <file.swift>";
  prerr_endline
    "       lab --emit-tokens|--emit-ast|--typecheck|--emit-sil|--emit-llvm \
     <file.swift>";
  exit 2

let emit_of_flag : string -> Driver.emit option = function
  | "--emit-tokens" -> Some Driver.Tokens
  | "--emit-ast" -> Some Driver.Ast
  | "--typecheck" -> Some Driver.Check
  | "--emit-tast" -> Some Driver.Typed_ast
  | "--emit-sil" -> Some Driver.Sil
  | "--emit-llvm" -> Some Driver.Llvm
  | _ -> None

let () =
  match Array.to_list Sys.argv with
  | _ :: "build" :: file :: rest ->
      let out =
        match rest with
        | [] -> Filename.remove_extension (Filename.basename file)
        | [ "-o"; o ] -> o
        | _ -> usage ()
      in
      Driver.compile_file ~out ~src_path:file ~emit:Driver.Exe ()
  | _ :: "--emit-spans" :: [ file ] ->
      (* the parser's spans, which --emit-ast does not print: each top-level expression (an
         expression statement, or a `let`/`var`'s value), then `line:col-line:col`, the end
         being one past its last character *)
      let source = Driver.read_file file in
      let diagnostics = Diagnostics.create ~source () in
      let program =
        Parser.parse_program
          (Parser.create (Lexer.tokenize (Lexer.create source diagnostics)) diagnostics)
      in
      Driver.bail_on_errors diagnostics;
      List.iter
        (function
          | Ast.IStmt (Ast.Expr_stmt (expression, _) | Ast.Let { value = expression; _ }) ->
              let span = Ast.expr_span expression in
              Printf.printf "%s %d:%d-%d:%d\n" (Ast.dump_expr expression)
                span.Token.lo.Token.line span.Token.lo.Token.col span.Token.hi.Token.line
                span.Token.hi.Token.col
          | _ -> ())
        program.Ast.items
  | _ :: flag :: [ file ] when emit_of_flag flag <> None ->
      Driver.compile_file ~src_path:file
        ~emit:(Option.get (emit_of_flag flag))
        ()
  | _ -> usage ()
