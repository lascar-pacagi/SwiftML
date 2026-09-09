(* Concept 09 runtime baseline: our LLVM with clang default/-O2 vs swiftc -Onone/-O.

   The benchmark checks correctness before timing. Timings are the best of five runs after
   one warm-up, which reduces process-startup and scheduler noise.

   Run from course/: make bench C=phase2-types-flow/09-sil-to-llvm *)

let source = "phase2-types-flow/09-sil-to-llvm/bench/programs/collatz.swift"
let runs = 5

let status_string : Unix.process_status -> string = function
  | Unix.WEXITED n -> Printf.sprintf "exit %d" n
  | Unix.WSIGNALED n -> Printf.sprintf "signal %d" n
  | Unix.WSTOPPED n -> Printf.sprintf "stopped by signal %d" n

let require_success what = function
  | Unix.WEXITED 0 -> ()
  | status -> failwith (Printf.sprintf "%s failed (%s)" what (status_string status))

let run_quiet prog argv =
  let null = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
  let pid = Unix.create_process prog argv Unix.stdin null null in
  let _, status = Unix.waitpid [] pid in
  Unix.close null;
  status

let compile_swiftc flag out =
  let argv = [| "/usr/bin/swiftc"; flag; source; "-o"; out |] in
  require_success ("swiftc " ^ flag) (run_quiet "/usr/bin/swiftc" argv)

let write_file path contents =
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc contents)

let compile_swiftml_o2 ll_path out =
  let src = Driver.read_file source in
  let llvm = Driver.to_llvm src (Diagnostics.create ()) in
  write_file ll_path llvm;
  let argv =
    [| "clang"; "-Wno-override-module"; "-O2"; ll_path; "-o"; out |]
  in
  require_success "clang -O2" (run_quiet "clang" argv)

let capture exe =
  let rd, wr = Unix.pipe () in
  let pid = Unix.create_process exe [| exe |] Unix.stdin wr Unix.stderr in
  Unix.close wr;
  let ic = Unix.in_channel_of_descr rd in
  let buf = Buffer.create 32 in
  let chunk = Bytes.create 4096 in
  let rec read () =
    match input ic chunk 0 (Bytes.length chunk) with
    | 0 -> ()
    | n ->
        Buffer.add_subbytes buf chunk 0 n;
        read ()
  in
  read ();
  close_in ic;
  let _, status = Unix.waitpid [] pid in
  require_success exe status;
  Buffer.contents buf

let time_once exe =
  let null = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
  let t0 = Unix.gettimeofday () in
  let pid = Unix.create_process exe [| exe |] Unix.stdin null null in
  let _, status = Unix.waitpid [] pid in
  let elapsed = Unix.gettimeofday () -. t0 in
  Unix.close null;
  require_success exe status;
  elapsed

let time_best exe =
  ignore (time_once exe);
  let best = ref max_float in
  for _ = 1 to runs do
    best := min !best (time_once exe)
  done;
  !best

let make_temp_dir () =
  let path = Filename.temp_file "swiftml-bench09-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let () =
  let tmp = make_temp_dir () in
  let ll = Filename.concat tmp "swiftml.ll" in
  let ml0 = Filename.concat tmp "swiftml-o0" in
  let ml2 = Filename.concat tmp "swiftml-o2" in
  let sc0 = Filename.concat tmp "swiftc-onone" in
  let sco = Filename.concat tmp "swiftc-o" in
  let scu = Filename.concat tmp "swiftc-ounchecked" in
  Fun.protect
    ~finally:(fun () ->
      List.iter
        (fun path -> if Sys.file_exists path then Sys.remove path)
        [ ll; ml0; ml2; sc0; sco; scu ];
      Unix.rmdir tmp)
    (fun () ->
      Driver.compile_file ~out:ml0 ~src_path:source ~emit:Driver.Exe ();
      compile_swiftml_o2 ll ml2;
      compile_swiftc "-Onone" sc0;
      compile_swiftc "-O" sco;
      compile_swiftc "-Ounchecked" scu;
      let reference = capture sco in
      List.iter
        (fun (name, exe) ->
          let output = capture exe in
          if output <> reference then
            failwith
              (Printf.sprintf "output mismatch: %s=%S swiftc=%S" name output reference))
        [ ("swiftml", ml0); ("swiftml + clang -O2", ml2); ("swiftc -Onone", sc0);
          ("swiftc -Ounchecked", scu) ];
      Printf.printf "IRGen runtime benchmark -- Collatz for starts 1..<500000\n";
      Printf.printf "  output: %s (all five binaries agree)\n" (String.trim reference);
      Printf.printf "  native runtime, best of %d after one warm-up:\n" runs;
      let ml0_time = time_best ml0 in
      let ml2_time = time_best ml2 in
      let sc0_time = time_best sc0 in
      let sco_time = time_best sco in
      let scu_time = time_best scu in
      Printf.printf "    swiftml (clang default)  %.3f s\n" ml0_time;
      Printf.printf "    swiftml + clang -O2      %.3f s\n" ml2_time;
      Printf.printf "    swiftc -Onone            %.3f s\n" sc0_time;
      Printf.printf "    swiftc -O                %.3f s\n" sco_time;
      Printf.printf "    swiftc -Ounchecked       %.3f s\n" scu_time;
      Printf.printf "  clang -O2 speedup: %.2fx\n" (ml0_time /. ml2_time);
      Printf.printf "  swiftc -O speedup: %.2fx\n" (sc0_time /. sco_time);
      Printf.printf "  unchecked gap: %.2fx (swiftc / swiftml)\n" (scu_time /. ml2_time))
