(* Optional §6 exercises. Guard is checked through the library. The two standalone SIL
   tools use documented lab flags, leaving their internal module structure unconstrained. *)

let errors source =
  let sink = Diagnostics.create () in
  (try
     let program =
       Parser.parse_program
         (Parser.create (Lexer.tokenize (Lexer.create source sink)) sink)
     in
     Sema.check program sink
   with _ -> ());
  Diagnostics.all sink
  |> List.filter (fun (diagnostic : Diagnostics.t) ->
      diagnostic.Diagnostics.severity = Diagnostics.Error)
  |> List.map (fun (diagnostic : Diagnostics.t) ->
      diagnostic.Diagnostics.message)

let sil source =
  let sink = Diagnostics.create () in
  let program = Driver.frontend source sink in
  if Diagnostics.has_errors sink then None
  else try Some (Sil.string_of_module (Silgen.lower program)) with _ -> None

let base_ready () =
  match sil "var n = 0\nwhile n < 2 { n = n + 1 }\nprint(n)" with
  | Some text -> Exercise_test_support.contains text "cond_br"
  | None -> false

let guard_program =
  "func positive(_ value: Int) -> Int {\n\
  \  guard value > 0 else { return 0 }\n\
  \  return value\n\
   }\n\
   print(positive(2))"

let ex1_started () =
  let sink = Diagnostics.create () in
  let tokens = Lexer.tokenize (Lexer.create "guard" sink) in
  base_ready ()
  && List.exists
       (fun (token : Token.t) ->
         Token.string_of_kind token.Token.kind = "guard")
       tokens

let test_guard () =
  Alcotest.(check (list string))
    "a leaving else is accepted" [] (errors guard_program);
  let text = Option.value (sil guard_program) ~default:"" in
  Alcotest.(check bool)
    "guard creates a conditional branch" true
    (Exercise_test_support.contains text "cond_br");
  Alcotest.(check bool)
    "an else that falls through is rejected" true
    (errors
       "func f(_ value: Int) -> Int {\n\
       \  guard value > 0 else { print(0) }\n\
       \  return value\n\
        }"
    <> [])

let sample_sil =
  "sil @main() -> $() {\n\
   \bb0:\n\
  \  %0 = integer_literal $Int, 7\n\
  \  %1 = apply @print(%0)\n\
  \  return\n\
   }\n"

let roundtrip text =
  Exercise_test_support.lab ~suffix:".sil" [ "--roundtrip-sil" ] text

let ex2_started () = base_ready () && (roundtrip sample_sil).status <> 2

let test_sil_reader () =
  let first = roundtrip sample_sil in
  Alcotest.(check int) "the reader accepts emitted SIL" 0 first.status;
  Alcotest.(check bool)
    "the module survives" true
    (Exercise_test_support.contains first.stdout "sil @main() -> $()");
  let second = roundtrip first.stdout in
  Alcotest.(check int) "the emitted result parses again" 0 second.status;
  Alcotest.(check string)
    "a second round trip is stable" first.stdout second.stdout

let parse_block_id line =
  try Some (Scanf.sscanf line "bb%d:" (fun block_id -> block_id))
  with _ -> None

let successors line =
  try [ Scanf.sscanf line "br bb%d" (fun target -> target) ]
  with _ -> (
    try
      Scanf.sscanf line "cond_br %%%d, bb%d, bb%d"
        (fun _ then_target else_target -> [ then_target; else_target ])
    with _ -> [])

let cfg text =
  let current = ref None and graph = ref [] in
  String.split_on_char '\n' text
  |> List.iter (fun raw_line ->
      let line = String.trim raw_line in
      match parse_block_id line with
      | Some block_id ->
          current := Some block_id;
          graph := (block_id, []) :: !graph
      | None -> (
          match (!current, successors line) with
          | Some block_id, (_ :: _ as targets) ->
              graph :=
                List.map
                  (fun (candidate, old_targets) ->
                    if candidate = block_id then (candidate, targets)
                    else (candidate, old_targets))
                  !graph
          | _ -> ()));
  !graph

let critical_edges text =
  let graph = cfg text in
  let predecessor_count target =
    List.fold_left
      (fun count (_, targets) ->
        count + if List.mem target targets then 1 else 0)
      0 graph
  in
  List.fold_left
    (fun count (_, targets) ->
      if List.length targets < 2 then count
      else
        count
        + List.fold_left
            (fun subtotal target ->
              subtotal + if predecessor_count target >= 2 then 1 else 0)
            0 targets)
    0 graph

let critical_source =
  "let left = true\nlet right = false\nif left || right { print(1) }"

let split_edges () =
  Exercise_test_support.lab [ "--split-critical-edges" ] critical_source

let ex3_started () =
  base_ready ()
  &&
  let result = split_edges () in
  result.status <> 2

let test_critical_edges () =
  let raw = Exercise_test_support.lab [ "--emit-sil" ] critical_source in
  Alcotest.(check bool)
    "the fixture really contains a critical edge" true
    (raw.status = 0 && critical_edges raw.stdout > 0);
  let result = split_edges () in
  Alcotest.(check int) "the pass succeeds" 0 result.status;
  Alcotest.(check int)
    "the transformed graph has no critical edge" 0
    (critical_edges result.stdout)

let () =
  Alcotest.run "exercises-08"
    [
      Exercise_test_support.group "1: guard" ex1_started test_guard;
      Exercise_test_support.group "2: SIL reader" ex2_started test_sil_reader;
      Exercise_test_support.group "3: critical edges" ex3_started
        test_critical_edges;
    ]
