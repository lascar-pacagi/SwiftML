(* Alcotest unit tests for concept-38: async/await lowering to the cooperative-executor runtime. *)
let lower (src : string) : Sil.modul =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  Silgen.lower p

let app_of nm = function Sil.Func_ref n -> n = nm | _ -> false
let count pred m =
  List.fold_left
    (fun a (f : Sil.func) ->
      List.fold_left (fun a (b : Sil.block) -> a + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs)) a f.Sil.blocks)
    0 m.Sil.funcs
let has_func m n = List.exists (fun (f : Sil.func) -> f.Sil.fname = n) m.Sil.funcs

let prog = "func worker(_ id: Int) async {\n  print(id)\n  await Task.yield()\n  print(id + 1)\n}\nTask { await worker(1) }\nTask { await worker(2) }"

let test_spawn_lifts_a_task () =
  let m = lower prog in
  (* each `Task { … }` becomes a lifted task function + an rt_async_spawn call *)
  Alcotest.(check bool) "a task closure was lifted" true (has_func m "main$task0");
  Alcotest.(check int) "two spawns" 2 (count (app_of "rt_async_spawn") m)

let test_yield_is_a_runtime_call () =
  let m = lower prog in
  Alcotest.(check bool) "Task.yield() -> rt_async_yield" true (count (app_of "rt_async_yield") m >= 1)

let test_main_drains_executor () =
  let m = lower prog in
  (* main ends by draining the executor *)
  Alcotest.(check int) "exactly one rt_async_run (in main)" 1 (count (app_of "rt_async_run") m)

let test_await_is_transparent () =
  (* `await e` lowers to just `e` — no extra runtime call, no new SIL: a plain async result *)
  let m = lower "func f() async -> Int { return 5 }\nlet x = await f()\nprint(x)" in
  Alcotest.(check int) "await adds no spawn" 0 (count (app_of "rt_async_spawn") m);
  Alcotest.(check (list string)) "valid SIL" [] (Sil.verify m)

let test_optimizer_safe () =
  let m = Opt.optimize (lower prog) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let () =
  Alcotest.run "async"
    [
      ( "lowering",
        [
          Alcotest.test_case "Task { } lifts a coroutine + spawns" `Quick test_spawn_lifts_a_task;
          Alcotest.test_case "Task.yield() -> runtime call" `Quick test_yield_is_a_runtime_call;
          Alcotest.test_case "main drains the executor" `Quick test_main_drains_executor;
          Alcotest.test_case "await is transparent" `Quick test_await_is_transparent;
        ] );
      ("optimizer", [ Alcotest.test_case "-O safe" `Quick test_optimizer_safe ]);
    ]
