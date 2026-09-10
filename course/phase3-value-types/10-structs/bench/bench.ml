(* Concept 10 runtime comparison: repeated copies of a six-field struct.

   The runner checks output before timing. Timings are the best of five executions after
   one warm-up. Run from course/:

     make bench C=phase3-value-types/10-structs *)

let source = "phase3-value-types/10-structs/bench/programs/struct-copy.swift"
let runs = 5

let status_string : Unix.process_status -> string = function
  | Unix.WEXITED code -> Printf.sprintf "exit %d" code
  | Unix.WSIGNALED signal -> Printf.sprintf "signal %d" signal
  | Unix.WSTOPPED signal -> Printf.sprintf "stopped by signal %d" signal

let require_success description = function
  | Unix.WEXITED 0 -> ()
  | status ->
      failwith
        (Printf.sprintf "%s failed (%s)" description (status_string status))

let run_quiet program arguments =
  let null = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
  let process_id = Unix.create_process program arguments Unix.stdin null null in
  let _, status = Unix.waitpid [] process_id in
  Unix.close null;
  status

let compile_swiftc optimization output =
  let arguments = [| "/usr/bin/swiftc"; optimization; source; "-o"; output |] in
  require_success ("swiftc " ^ optimization)
    (run_quiet "/usr/bin/swiftc" arguments)

let write_file path contents =
  let output_channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out output_channel)
    (fun () -> output_string output_channel contents)

let compile_swiftml_o2 llvm_path output =
  let source_text = Driver.read_file source in
  let llvm_ir = Driver.to_llvm source_text (Diagnostics.create ()) in
  write_file llvm_path llvm_ir;
  let arguments =
    [| "clang"; "-Wno-override-module"; "-O2"; llvm_path; "-o"; output |]
  in
  require_success "clang -O2" (run_quiet "clang" arguments)

let capture_output executable =
  let read_descriptor, write_descriptor = Unix.pipe () in
  let process_id =
    Unix.create_process executable [| executable |] Unix.stdin write_descriptor
      Unix.stderr
  in
  Unix.close write_descriptor;
  let input_channel = Unix.in_channel_of_descr read_descriptor in
  let buffer = Buffer.create 32 in
  let chunk = Bytes.create 4096 in
  let rec read () =
    match input input_channel chunk 0 (Bytes.length chunk) with
    | 0 -> ()
    | count ->
        Buffer.add_subbytes buffer chunk 0 count;
        read ()
  in
  read ();
  close_in input_channel;
  let _, status = Unix.waitpid [] process_id in
  require_success executable status;
  Buffer.contents buffer

let time_once executable =
  let null = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
  let start_time = Unix.gettimeofday () in
  let process_id =
    Unix.create_process executable [| executable |] Unix.stdin null null
  in
  let _, status = Unix.waitpid [] process_id in
  let elapsed = Unix.gettimeofday () -. start_time in
  Unix.close null;
  require_success executable status;
  elapsed

let time_best executable =
  ignore (time_once executable);
  let best = ref max_float in
  for _ = 1 to runs do
    best := min !best (time_once executable)
  done;
  !best

let time_and_report label executable =
  let elapsed = time_best executable in
  Printf.printf "    %-27s %.3f s\n%!" label elapsed;
  elapsed

let make_temp_directory () =
  let path = Filename.temp_file "swiftml-bench10-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let () =
  let temporary_directory = make_temp_directory () in
  let llvm_path = Filename.concat temporary_directory "swiftml.ll" in
  let swiftml_o0 = Filename.concat temporary_directory "swiftml-o0" in
  let swiftml_o2 = Filename.concat temporary_directory "swiftml-o2" in
  let swiftc_onone = Filename.concat temporary_directory "swiftc-onone" in
  let swiftc_o = Filename.concat temporary_directory "swiftc-o" in
  Fun.protect
    ~finally:(fun () ->
      List.iter
        (fun path -> if Sys.file_exists path then Sys.remove path)
        [ llvm_path; swiftml_o0; swiftml_o2; swiftc_onone; swiftc_o ];
      Unix.rmdir temporary_directory)
    (fun () ->
      Printf.printf "Struct value benchmark -- 50,000,000 six-field updates\n%!";
      Printf.printf "  compiling and checking four binaries...%!";
      Driver.compile_file ~out:swiftml_o0 ~src_path:source ~emit:Driver.Exe ();
      compile_swiftml_o2 llvm_path swiftml_o2;
      compile_swiftc "-Onone" swiftc_onone;
      compile_swiftc "-O" swiftc_o;
      let reference_output = capture_output swiftc_o in
      List.iter
        (fun (name, executable) ->
          let output = capture_output executable in
          if output <> reference_output then
            failwith
              (Printf.sprintf "output mismatch: %s=%S swiftc=%S" name output
                 reference_output))
        [
          ("swiftml", swiftml_o0);
          ("swiftml + clang -O2", swiftml_o2);
          ("swiftc -Onone", swiftc_onone);
        ];
      Printf.printf " done\n%!";
      Printf.printf "  output: %s (all four binaries agree)\n%!"
        (String.trim reference_output);
      Printf.printf "  native runtime, best of %d after one warm-up:\n%!" runs;
      let swiftml_o0_time =
        time_and_report "swiftml (clang default)" swiftml_o0
      in
      let swiftml_o2_time = time_and_report "swiftml + clang -O2" swiftml_o2 in
      let swiftc_onone_time = time_and_report "swiftc -Onone" swiftc_onone in
      let swiftc_o_time = time_and_report "swiftc -O" swiftc_o in
      Printf.printf "  clang -O2 speedup: %.2fx\n"
        (swiftml_o0_time /. swiftml_o2_time);
      Printf.printf "  swiftc -O speedup: %.2fx\n"
        (swiftc_onone_time /. swiftc_o_time);
      Printf.printf "  optimized gap: %.2fx (swiftml / swiftc)\n"
        (swiftml_o2_time /. swiftc_o_time))
