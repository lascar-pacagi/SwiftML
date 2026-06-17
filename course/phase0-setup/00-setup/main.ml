(* M0 — the smallest possible end-to-end compiler, fully self-contained.

   Language: a program is a single integer literal; its value becomes the process
   exit code. This proves the whole pipeline works:
       source  ->  LLVM IR  ->  clang  ->  arm64 executable  ->  run
   It depends on nothing else — Phase 1 builds the real lexer/parser/sema/codegen
   that subsumes it. Throw this away once Phase 1's pipeline exists.

   Invoked as:  swiftml-m0 <file.swift> [-o <out>] *)

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

(* "Parse" the trivial language: strip // line comments + whitespace, expect one int. *)
let parse_int src =
  let strip_comment line =
    match String.index_opt line '/' with
    | Some i when i + 1 < String.length line && line.[i + 1] = '/' -> String.sub line 0 i
    | _ -> line
  in
  let cleaned =
    String.split_on_char '\n' src |> List.map strip_comment |> String.concat " " |> String.trim
  in
  match int_of_string_opt cleaned with
  | Some n -> n
  | None -> failwith (Printf.sprintf "M0 expects a single integer literal, got: %S" cleaned)

let emit_llvm n = Printf.sprintf "define i32 @main() {\nentry:\n  ret i32 %d\n}\n" n

let run_clang ~ll_path ~out =
  (* -Wno-override-module: our IR omits a target triple on purpose; clang fills in the host. *)
  let cmd =
    Printf.sprintf "clang -Wno-override-module %s -o %s" (Filename.quote ll_path)
      (Filename.quote out)
  in
  if Sys.command cmd <> 0 then failwith "clang failed"

let usage () =
  prerr_endline "usage: swiftml-m0 <file.swift> [-o <out>]";
  exit 2

let () =
  match Array.to_list Sys.argv with
  | _ :: file :: rest ->
      let out =
        match rest with
        | [] -> Filename.remove_extension (Filename.basename file)
        | [ "-o"; o ] -> o
        | _ -> usage ()
      in
      let n = parse_int (read_file file) in
      let ll_path = Filename.temp_file "swiftml_m0" ".ll" in
      Fun.protect
        ~finally:(fun () -> try Sys.remove ll_path with _ -> ())
        (fun () ->
          let oc = open_out ll_path in
          output_string oc (emit_llvm n);
          close_out oc;
          run_clang ~ll_path ~out)
  | _ -> usage ()
