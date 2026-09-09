(* Concept 09 runtime baseline: raw SIL -> raw LLVM vs swiftc -O.

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

let compile_swiftc out =
  let argv = [| "/usr/bin/swiftc"; "-O"; source; "-o"; out |] in
  require_success "swiftc -O" (run_quiet "/usr/bin/swiftc" argv)

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
  let ml = Filename.concat tmp "swiftml" in
  let sc = Filename.concat tmp "swiftc" in
  Fun.protect
    ~finally:(fun () ->
      List.iter (fun path -> if Sys.file_exists path then Sys.remove path) [ ml; sc ];
      Unix.rmdir tmp)
    (fun () ->
      Driver.compile_file ~out:ml ~src_path:source ~emit:Driver.Exe ();
      compile_swiftc sc;
      let ml_output = capture ml in
      let sc_output = capture sc in
      if ml_output <> sc_output then
        failwith
          (Printf.sprintf "output mismatch: swiftml=%S swiftc=%S" ml_output sc_output);
      Printf.printf "IRGen runtime benchmark -- Collatz for starts 1..<500000\n";
      Printf.printf "  output: %s (swiftml == swiftc)\n" (String.trim ml_output);
      Printf.printf "  native runtime, best of %d after one warm-up:\n" runs;
      let ml_time = time_best ml in
      let sc_time = time_best sc in
      Printf.printf "    swiftml       %.3f s\n" ml_time;
      Printf.printf "    swiftc -O     %.3f s\n" sc_time;
      Printf.printf "    ratio         %.2fx swiftc -O\n" (ml_time /. sc_time))
