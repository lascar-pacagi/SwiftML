type result = { status : int; stdout : string; stderr : string }

let read_file path =
  let input_channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in input_channel)
    (fun () ->
      really_input_string input_channel (in_channel_length input_channel))

let exit_code = function
  | Unix.WEXITED code -> code
  | Unix.WSIGNALED signal | Unix.WSTOPPED signal -> 128 + signal

(* Exercise implementations may contain the same non-advancing loop as a main lab hole.
   Run every black-box probe out of process, with its own deadline, so an optional exercise
   can fail but can never hang [make lab]. *)
let run ?(timeout = 5.) (arguments : string array) : result =
  let stdout_path = Filename.temp_file "swiftml-exercise" ".out" in
  let stderr_path = Filename.temp_file "swiftml-exercise" ".err" in
  Fun.protect
    ~finally:(fun () ->
      List.iter
        (fun path -> try Sys.remove path with Sys_error _ -> ())
        [ stdout_path; stderr_path ])
    (fun () ->
      let stdin_fd = Unix.openfile "/dev/null" [ Unix.O_RDONLY ] 0 in
      let stdout_fd =
        Unix.openfile stdout_path [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600
      in
      let stderr_fd =
        Unix.openfile stderr_path [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600
      in
      let pid =
        Fun.protect
          ~finally:(fun () ->
            Unix.close stdin_fd;
            Unix.close stdout_fd;
            Unix.close stderr_fd)
          (fun () ->
            Unix.create_process arguments.(0) arguments stdin_fd stdout_fd
              stderr_fd)
      in
      let deadline = Unix.gettimeofday () +. timeout in
      let rec wait () =
        match Unix.waitpid [ Unix.WNOHANG ] pid with
        | 0, _ when Unix.gettimeofday () < deadline ->
            Unix.sleepf 0.02;
            wait ()
        | 0, _ ->
            Unix.kill pid Sys.sigkill;
            ignore (Unix.waitpid [] pid);
            124
        | _, process_status -> exit_code process_status
      in
      let status = wait () in
      { status; stdout = read_file stdout_path; stderr = read_file stderr_path })

let with_input ?(suffix = ".swift") contents action =
  let path = Filename.temp_file "swiftml-exercise" suffix in
  Fun.protect
    ~finally:(fun () -> try Sys.remove path with Sys_error _ -> ())
    (fun () ->
      let output_channel = open_out_bin path in
      output_string output_channel contents;
      close_out output_channel;
      action path)

let lab ?(suffix = ".swift") arguments contents =
  with_input ~suffix contents (fun path ->
      run (Array.of_list (("./lab.exe" :: arguments) @ [ path ])))

let build_and_run contents =
  with_input contents (fun source_path ->
      let executable_path = Filename.temp_file "swiftml-exercise" ".exe" in
      Sys.remove executable_path;
      Fun.protect
        ~finally:(fun () ->
          try Sys.remove executable_path with Sys_error _ -> ())
        (fun () ->
          let built =
            run [| "./lab.exe"; "build"; source_path; "-o"; executable_path |]
          in
          if built.status = 0 then run [| executable_path |] else built))

let contains text fragment =
  let text_length = String.length text
  and fragment_length = String.length fragment in
  let rec search offset =
    offset + fragment_length <= text_length
    && (String.sub text offset fragment_length = fragment || search (offset + 1))
  in
  fragment_length = 0 || search 0

let group name started test =
  ( name,
    [
      (if try started () with _ -> false then
         Alcotest.test_case "checked" `Quick test
       else Alcotest.test_case "skipped — not started" `Quick (fun () -> ()));
    ] )
