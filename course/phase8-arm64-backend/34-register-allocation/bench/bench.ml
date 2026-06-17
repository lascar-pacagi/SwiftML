(* The register-allocation ladder benchmark (concept 34): for each program, compile it with each
   rung — STACK (spill all), LINEAR-SCAN, GRAPH-COLOUR — plus our LLVM `-O` path as a reference,
   CHECK the four outputs agree (a benchmark of wrong code is worthless), then time each (best of
   [runs]). The point: each rung beats the last, and graph-colour approaches the LLVM path.
   Run from `course/`: make bench C=phase8-arm64-backend/34-register-allocation *)

let dir = "phase8-arm64-backend/34-register-allocation/bench"
let programs = [ "hotloop"; "collatz"; "fibloop" ]
let runs = 3

let sh (cmd : string) : int = Sys.command (cmd ^ " > /dev/null 2>&1")

let output_of (cmd : string) : string =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 64 in
  (try while true do Buffer.add_channel buf ic 1 done with End_of_file -> ());
  ignore (Unix.close_process_in ic);
  String.trim (Buffer.contents buf)

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
  ignore (one ()); (* warm-up: macOS code-sign verification + page cache *)
  List.fold_left (fun best _ -> min best (one ())) (one ()) (List.init (runs - 1) Fun.id)

let () =
  let tmp = Filename.temp_file "swiftml-ra-bench" "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  Printf.printf "%-10s %12s %12s %12s %12s %14s\n" "bench" "stack" "linscan" "graphcolor" "(llvm -O)" "gc vs stack";
  let geo = ref 1.0 and n = ref 0 in
  List.iter
    (fun name ->
      let src = Printf.sprintf "%s/programs/%s.swift" dir name in
      let exe v = Filename.concat tmp (name ^ "-" ^ v) in
      Driver.compile_file ~out:(exe "stack") ~native:true ~regalloc:Regalloc.Stack ~src_path:src ~emit:Driver.Exe ();
      Driver.compile_file ~out:(exe "lin") ~native:true ~regalloc:Regalloc.Linscan ~src_path:src ~emit:Driver.Exe ();
      Driver.compile_file ~out:(exe "gc") ~native:true ~regalloc:Regalloc.Graphcolor ~src_path:src ~emit:Driver.Exe ();
      Driver.compile_file ~out:(exe "llvm") ~opt:true ~src_path:src ~emit:Driver.Exe ();
      (* correctness: all four must agree (use swiftc as the reference) *)
      if sh (Printf.sprintf "swiftc -O %s -o %s" src (exe "sc")) <> 0 then failwith ("swiftc failed on " ^ src);
      let reference = output_of (exe "sc") in
      List.iter
        (fun v ->
          let got = output_of (exe v) in
          if got <> reference then failwith (Printf.sprintf "%s (%s): expected %s, got %s" name v reference got))
        [ "stack"; "lin"; "gc"; "llvm" ];
      let ts = time_best (exe "stack") and tl = time_best (exe "lin") in
      let tg = time_best (exe "gc") and tv = time_best (exe "llvm") in
      let speedup = ts /. tg in
      geo := !geo *. speedup;
      incr n;
      Printf.printf "%-10s %11.3fs %11.3fs %11.3fs %11.3fs %12.1fx\n" name ts tl tg tv speedup)
    programs;
  Printf.printf "%-10s %50s %12.1fx\n" "geomean" "" (Float.pow !geo (1.0 /. float_of_int !n));
  ignore (sh (Printf.sprintf "rm -rf %s" (Filename.quote tmp)))
