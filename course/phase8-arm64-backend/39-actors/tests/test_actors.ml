(* Alcotest unit tests for concept-39: actor isolation (the compile-time rule). *)
let check (src : string) =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  d

let msgs d = List.rev_map (fun (e : Diagnostics.t) -> e.Diagnostics.message) d.Diagnostics.diags
let has_isolation d = List.exists (fun s -> String.length s >= 7 && String.sub s 0 7 = "call to") (msgs d)

let actor =
  "actor Counter {\n  var value: Int\n  init() { value = 0 }\n  func bump() { value = value + 1 }\n  func get() -> Int { return value }\n}\n"

(* a synchronous, non-awaited call to an actor method from the top level is ISOLATED -> rejected *)
let test_sync_rejected () =
  let d = check (actor ^ "let c = Counter()\nprint(c.get())") in
  Alcotest.(check bool) "sync actor call rejected" true (has_isolation d)

(* the same call under `await` is fine — it hops onto the actor's executor *)
let test_await_accepted () =
  let d = check (actor ^ "let c = Counter()\nawait c.bump()\nprint(await c.get())") in
  Alcotest.(check bool) "awaited actor call accepted" false (Diagnostics.has_errors d)

(* INSIDE the actor, access is synchronous (an actor method calling another) *)
let test_inside_actor_sync () =
  let d =
    check
      "actor A {\n  var v: Int\n  init() { v = 0 }\n  func step() { v = v + 1 }\n  func twice() { self.step()\n    self.step() }\n  func get() -> Int { return v }\n}\nlet a = A()\nawait a.twice()\nprint(await a.get())"
  in
  Alcotest.(check bool) "inside-actor sync access accepted" false (Diagnostics.has_errors d)

(* a REGULAR class is not isolated — synchronous calls need no await *)
let test_regular_class_unaffected () =
  let d = check "class P { var x: Int\n  init() { x = 5 }\n  func get() -> Int { return x } }\nlet p = P()\nprint(p.get())" in
  Alcotest.(check bool) "regular class call accepted" false (Diagnostics.has_errors d)

let () =
  Alcotest.run "actors"
    [
      ( "isolation",
        [
          Alcotest.test_case "sync actor call rejected" `Quick test_sync_rejected;
          Alcotest.test_case "awaited actor call accepted" `Quick test_await_accepted;
          Alcotest.test_case "inside actor is synchronous" `Quick test_inside_actor_sync;
          Alcotest.test_case "regular class unaffected" `Quick test_regular_class_unaffected;
        ] );
    ]
