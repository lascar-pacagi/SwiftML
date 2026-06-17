(* concept-14 lab CLI — --emit-layout against THIS concept's library *)
let () =
  match Array.to_list Sys.argv with
  | _ :: "--emit-layout" :: [ file ] ->
      let ic = open_in_bin file in
      let src = Fun.protect ~finally:(fun () -> close_in ic) (fun () -> really_input_string ic (in_channel_length ic)) in
      Driver.compile_file ~src_path:file ~emit:Driver.Layout () |> ignore;
      ignore src
  | _ -> prerr_endline "usage: lab --emit-layout <file.swift>"; exit 2
