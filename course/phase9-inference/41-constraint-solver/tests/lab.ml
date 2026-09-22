(* The lab binary the cram tests call, built from THIS concept's library. *)
let () =
  let args = Array.to_list Sys.argv in
  match args with
  | _ :: "--emit-tokens" :: path :: _ -> Driver.compile_file ~src_path:path ~emit:Driver.Tokens
  | _ :: "--emit-ast" :: path :: _ -> Driver.compile_file ~src_path:path ~emit:Driver.Ast
  | _ :: "--emit-constraints" :: path :: _ ->
      Driver.compile_file ~src_path:path ~emit:Driver.Constraints_
  | _ :: "--typecheck" :: path :: _ -> Driver.compile_file ~src_path:path ~emit:Driver.Check
  | _ :: "--emit-tast" :: path :: _ -> Driver.compile_file ~src_path:path ~emit:Driver.Typed_ast
  | _ ->
      prerr_endline
        "usage: lab --emit-tokens|--emit-ast|--emit-constraints|--typecheck|--emit-tast <file>";
      exit 2
