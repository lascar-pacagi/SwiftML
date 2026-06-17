(* The Milestone-M4 benchmark: swiftml vs swiftc, -Onone and -O, on the microbench suite.
   For each program: compile all four ways, CHECK the outputs agree (a benchmark of wrong code is
   worthless), then time each binary (best of [runs], to shed scheduler noise) and report runtimes
   plus swiftml -O as a percentage of swiftc -O speed (100% = parity; higher = we're faster).
   Run from `course/`: make bench C=phase6-classes-arc/28-arc-optimization *)

let dir = "phase6-classes-arc/28-arc-optimization/bench"
let programs = [ "borrowloop"; "handoff" ]
let runs = 3

let sh (cmd : string) : int = Sys.command (cmd ^ " > /dev/null 2>&1")

let output_of (cmd : string) : string =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 64 in
  (try
     while true do
       Buffer.add_channel buf ic 1
     done
   with End_of_file -> ());
  ignore (Unix.close_process_in ic);
  String.trim (Buffer.contents buf)

(* wall-clock the best of [runs] executions of an already-built binary. Methodology notes:
   - spawn the binary DIRECTLY (no `sh -c` wrapper) with stdout to /dev/null;
   - one WARM-UP run first — on macOS the first exec of a fresh binary stalls ~300ms in
     code-signature verification, which would swamp the measurement;
   - take the BEST of the timed runs (the minimum is the run with the least scheduler noise). *)
let time_best (exe : string) : float =
  let one () =
    let null = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
    let t0 = Unix.gettimeofday () in
    let pid = Unix.create_process exe [| exe |] Unix.stdin null null in
    let _, status = Unix.waitpid [] pid in
    let dt = Unix.gettimeofday () -. t0 in
    Unix.close null;
    if status <> Unix.WEXITED 0 then failwith (exe ^ " exited nonzero");
    dt
  in
  ignore (one ());
  (* warm-up: code-sign verification + page cache *)
  List.fold_left (fun best _ -> min best (one ())) (one ()) (List.init (runs - 1) Fun.id)

let () =
  let tmp = Filename.temp_file "swiftml-bench" "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  Printf.printf "%-10s %12s %12s %12s %12s %10s\n" "bench" "swiftml -On" "swiftml -O" "swiftc -On" "swiftc -O" "% of -O";
  let geo = ref 1.0 and n = ref 0 in
  List.iter
    (fun name ->
      let src = Printf.sprintf "%s/programs/%s.swift" dir name in
      let exe variant = Filename.concat tmp (name ^ "-" ^ variant) in
      (* compile all four ways; our compiler is invoked as a library (no subprocess) *)
      Driver.compile_file ~out:(exe "ml0") ~opt:false ~src_path:src ~emit:Driver.Exe ();
      Driver.compile_file ~out:(exe "mlO") ~opt:true ~src_path:src ~emit:Driver.Exe ();
      if sh (Printf.sprintf "swiftc -Onone %s -o %s" src (exe "sc0")) <> 0 then failwith ("swiftc -Onone failed on " ^ src);
      if sh (Printf.sprintf "swiftc -O %s -o %s" src (exe "scO")) <> 0 then failwith ("swiftc -O failed on " ^ src);
      (* correctness first: all four binaries must print the same thing *)
      let reference = output_of (exe "sc0") in
      List.iter
        (fun v ->
          let got = output_of (exe v) in
          if got <> reference then failwith (Printf.sprintf "%s (%s): expected %s, got %s" name v reference got))
        [ "ml0"; "mlO"; "scO" ];
      let t_ml0 = time_best (exe "ml0") and t_mlO = time_best (exe "mlO") in
      let t_sc0 = time_best (exe "sc0") and t_scO = time_best (exe "scO") in
      let pct = t_scO /. t_mlO *. 100.0 in
      geo := !geo *. pct;
      incr n;
      Printf.printf "%-10s %11.3fs %11.3fs %11.3fs %11.3fs %9.0f%%\n" name t_ml0 t_mlO t_sc0 t_scO pct)
    programs;
  Printf.printf "%-10s %s %38s %9.0f%%\n" "geomean" "" "" (Float.pow !geo (1.0 /. float_of_int !n));
  ignore (sh (Printf.sprintf "rm -rf %s" (Filename.quote tmp)))
