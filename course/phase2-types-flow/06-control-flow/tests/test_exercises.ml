(* Optional §6 exercises. Each group stays green and reports "not started" until its
   observable probe changes. Once started, incomplete work fails normally. *)

let diagnostics source =
  let sink = Diagnostics.create () in
  (try
     let program =
       Parser.parse_program
         (Parser.create (Lexer.tokenize (Lexer.create source sink)) sink)
     in
     Sema.check program sink
   with _ -> ());
  Diagnostics.all sink

let messages ?severity source =
  diagnostics source
  |> List.filter (fun (diagnostic : Diagnostics.t) ->
      match severity with
      | None -> true
      | Some expected -> diagnostic.Diagnostics.severity = expected)
  |> List.map (fun (diagnostic : Diagnostics.t) ->
      diagnostic.Diagnostics.message)

let errors source = messages ~severity:Diagnostics.Error source
let warnings source = messages ~severity:Diagnostics.Warning source

let token_kinds source =
  let sink = Diagnostics.create () in
  Lexer.tokenize (Lexer.create source sink)
  |> List.map (fun (token : Token.t) -> Token.string_of_kind token.Token.kind)

let parsed source =
  let sink = Diagnostics.create () in
  let program =
    Parser.parse_program
      (Parser.create (Lexer.tokenize (Lexer.create source sink)) sink)
  in
  (Ast.dump_program program, Diagnostics.has_errors sink)

let base_ready () =
  errors "var n = 0\nwhile n < 2 { n = n + 1 }\nprint(n)" = []
  && errors "if 1 { print(1) }" <> []

let ex1_started () = base_ready () && List.mem "repeat" (token_kinds "repeat")

let test_repeat () =
  Alcotest.(check (list string))
    "a repeat loop is accepted" []
    (errors "var n = 0\nrepeat { n = n + 1 } while n < 2");
  Alcotest.(check (list string))
    "its body has loop context" []
    (errors "repeat { break } while true");
  Alcotest.(check bool)
    "its condition must be Bool" true
    (List.mem "cannot convert value of type 'Int' to specified type 'Bool'"
       (errors "repeat { print(1) } while 1"))

let ex2_started () = base_ready () && List.mem "..." (token_kinds "1...3")

let test_closed_range () =
  let closed, closed_failed = parsed "for i in 1 ... 3 { print(i) }" in
  let half_open, half_open_failed = parsed "for i in 1 ..< 3 { print(i) }" in
  Alcotest.(check bool) "closed range parses" false closed_failed;
  Alcotest.(check bool) "half-open range still parses" false half_open_failed;
  Alcotest.(check bool)
    "the AST preserves which range was written" true (closed <> half_open);
  Alcotest.(check bool)
    "closed bounds still require Int" true
    (List.mem "cannot convert value of type 'Double' to specified type 'Int'"
       (errors "for i in 1 ... 3.5 { print(i) }"))

let ex3_started () =
  base_ready () && warnings "while true {\n  break\n  print(1)\n}" <> []

let test_reachability () =
  Alcotest.(check (list string))
    "after break"
    [ "code after 'break' will never be executed" ]
    (warnings "while true {\n  break\n  print(1)\n}");
  Alcotest.(check (list string))
    "after continue"
    [ "code after 'continue' will never be executed" ]
    (warnings "while true {\n  continue\n  print(1)\n}");
  Alcotest.(check (list string))
    "a conditional break does not make the tail unreachable" []
    (warnings "while true {\n  if true { break }\n  print(1)\n  break\n}")

let () =
  Alcotest.run "exercises-06"
    [
      Exercise_test_support.group "1: repeat-while" ex1_started test_repeat;
      Exercise_test_support.group "2: closed ranges" ex2_started
        test_closed_range;
      Exercise_test_support.group "3: reachability" ex3_started
        test_reachability;
    ]
