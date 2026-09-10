(* Alcotest unit tests for concept-06 sema: control-flow type rules. *)

let errors (src : string) : string list =
  let d = Diagnostics.create () in
  let p =
    Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d)
  in
  Sema.check p d;
  Diagnostics.all d
  |> List.filter (fun (x : Diagnostics.t) ->
      x.Diagnostics.severity = Diagnostics.Error)
  |> List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message)

let accepted src =
  Alcotest.(check (list string))
    (Printf.sprintf "accept %S" src)
    [] (errors src)

let has_error src msg =
  Alcotest.(check bool)
    (Printf.sprintf "%S => %S" src msg)
    true
    (List.mem msg (errors src))

(* the exact list, in order — catches a rule that reports twice, or in the wrong order *)
let reports src msgs =
  Alcotest.(check (list string))
    (Printf.sprintf "reports %S" src)
    msgs (errors src)

let n_errors src n =
  Alcotest.(check int)
    (Printf.sprintf "%S reports %d" src n)
    n
    (List.length (errors src))

let test_accept () =
  accepted "var n = 0\nwhile n < 3 { n = n + 1 }\nprint(n)";
  accepted
    "let x = 5\n\
     if x < 0 { print(x) } else if x == 0 { print(0) } else { print(1) }";
  accepted "for i in 0 ..< 10 { print(i) }";
  accepted "let a = true\nlet b = false\nif a && b || a { print(1) }";
  accepted
    "for i in 0 ..< 5 {\n  if i == 2 { continue }\n  if i == 4 { break }\n}"

let test_conditions () =
  has_error "if 1 { print(1) }"
    "cannot convert value of type 'Int' to specified type 'Bool'";
  has_error "while 3 { print(1) }"
    "cannot convert value of type 'Int' to specified type 'Bool'";
  has_error "let b = 1 && true"
    "binary operator '&&' cannot be applied to operands of type 'Int' and \
     'Bool'"

let test_loops () =
  has_error "break" "'break' is only allowed inside a loop";
  has_error "continue" "'continue' is only allowed inside a loop";
  has_error "for i in 0 ..< 3 { i = 9 }"
    "cannot assign to value: 'i' is a 'let' constant";
  has_error "for i in 0 ..< 3.5 { print(i) }"
    "cannot convert value of type 'Double' to specified type 'Int'"

let test_scope () =
  (* a binding made inside a block does not leak out of it *)
  has_error "if true { let z = 1 }\nprint(z)" "cannot find 'z' in scope";
  (* but the outer scope is visible inside the block *)
  accepted "let outer = 1\nif true { print(outer) }";
  (* the then- and else-blocks are siblings: neither sees the other's bindings *)
  has_error "if true {\n  let a = 1\n} else {\n  print(a)\n}"
    "cannot find 'a' in scope";
  (* an inner binding shadows an outer one, of any type, and the outer one comes back *)
  accepted
    "let x = 1\nif true {\n  let x = \"s\"\n  print(x)\n}\nlet y: Int = x";
  (* a block may assign an outer var, and read it in the same breath *)
  accepted "var n = 0\nwhile n < 3 {\n  n = n + 1\n}\nprint(n)";
  (* three levels of nesting, each its own scope *)
  accepted
    "for i in 0 ..< 3 {\n\
    \  var j = 0\n\
    \  while j < i {\n\
    \    if j == 1 { print(j) }\n\
    \    j = j + 1\n\
    \  }\n\
     }"

(* Every rule reports ONCE, and a run reports everything it can see — the two properties a
   report-and-recover checker must have, and the ones a wrong `err`/return pair breaks. *)
let test_recovery () =
  n_errors "if 1 { }" 1;
  n_errors "break\ncontinue" 2;
  reports "for i in \"a\" ..< true {\n}"
    [
      "cannot convert value of type 'String' to specified type 'Int'";
      "cannot convert value of type 'Bool' to specified type 'Int'";
    ];
  (* the body is still checked when the bounds are wrong *)
  reports "for i in 0.0 ..< 3 {\n  print(nope)\n}"
    [
      "cannot convert value of type 'Double' to specified type 'Int'";
      "cannot find 'nope' in scope";
    ];
  (* a bad condition does not stop the block under it *)
  reports "if 1 {\n  print(nope)\n}"
    [
      "cannot convert value of type 'Int' to specified type 'Bool'";
      "cannot find 'nope' in scope";
    ]

(* The loop-depth counter goes back down: what matters is where a statement SITS. *)
let test_loop_context () =
  accepted "while true {\n  if true { break }\n}";
  has_error "while true {\n  break\n}\nbreak"
    "'break' is only allowed inside a loop";
  has_error "if true {\n  continue\n}"
    "'continue' is only allowed inside a loop";
  (* an inner loop's break belongs to it, and the outer loop still counts afterwards *)
  accepted "for i in 0 ..< 3 {\n  while true { break }\n  continue\n}"

(* A watchdog. The holes in this concept are LOOPS — a `parse_block` that forgets to advance
   never returns — and alcotest runs in-process, so without this the suite hangs instead of
   failing. The cram files use `timeout 5`; this is the same guard for the unit tests. *)
let () =
  Sys.set_signal Sys.sigalrm
    (Sys.Signal_handle
       (fun _ ->
         prerr_endline
           "TIMEOUT after 30s — a test never finished. A loop that does not \
            advance the parser?";
         exit 124));
  ignore (Unix.alarm 30)

let () =
  Alcotest.run "sema-flow"
    [
      ( "accept",
        [ Alcotest.test_case "well-typed control flow" `Quick test_accept ] );
      ( "conditions",
        [
          Alcotest.test_case "Bool conditions & logical ops" `Quick
            test_conditions;
        ] );
      ( "loops",
        [
          Alcotest.test_case "loop var, ranges, break/continue" `Quick
            test_loops;
        ] );
      ("scope", [ Alcotest.test_case "lexical block scope" `Quick test_scope ]);
      ( "recovery",
        [
          Alcotest.test_case "one error each, all of them" `Quick test_recovery;
        ] );
      ( "loop context",
        [ Alcotest.test_case "depth goes back down" `Quick test_loop_context ]
      );
    ]
