(* The concept `lab` CLI — linked against THIS concept's library, so the cram tests in this
   directory exercise YOUR irgen.ml through the given Driver (the phase binary `swiftml` is
   the same wiring; this one is built from this directory's code).
     ./lab.exe --emit-llvm <file>          print the LLVM IR module          (TODO(04d), needs all)
     ./lab.exe build <file> -o <exe>       IR → clang → a native executable
   Diagnostics go to stderr, exit 1; an unfinished hole surfaces as its TODO exception. *)

let () =
  match Array.to_list Sys.argv with
  | [ _; "--emit-llvm"; file ] -> Driver.compile_file ~src_path:file ~out:"/dev/null" ~emit:Driver.Llvm
  | [ _; "build"; file; "-o"; out ] -> Driver.compile_file ~src_path:file ~out ~emit:Driver.Exe
  | _ ->
      prerr_endline "usage: lab --emit-llvm <file.swift> | lab build <file.swift> -o <exe>";
      exit 2
