(* Alcotest unit tests for concept-32: map / filter / reduce lowering over the array buffer. *)
let front (src : string) =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  (p, d)

let msgs d = List.rev_map (fun (e : Diagnostics.t) -> e.Diagnostics.message) d.Diagnostics.diags

let lower s =
  let p, d = front s in
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  Silgen.lower p

let count pred m =
  List.fold_left
    (fun a (f : Sil.func) ->
      List.fold_left
        (fun a (b : Sil.block) -> a + List.length (List.filter (fun (_, i) -> pred i) b.Sil.instrs))
        a f.Sil.blocks)
    0 m.Sil.funcs

let app_of nm = function Sil.Func_ref n -> n = nm | _ -> false
let is_apply_value = function Sil.Apply_value _ -> true | _ -> false

let mapprog = "let a = [1,2,3]\nlet b = a.map({ (x: Int) -> Int in x * 2 })\nprint(b[0])"
let filterprog = "let a = [1,2,3,4]\nlet b = a.filter({ (x: Int) -> Bool in x % 2 == 0 })\nprint(b.count)"
let reduceprog = "let a = [1,2,3]\nprint(a.reduce(0, { (s: Int, x: Int) -> Int in s + x }))"

let test_map_calls_closure () =
  (* map walks the buffer (array_get) and calls the closure per element (apply_value),
     building one fresh result array (array_new) *)
  let m = lower mapprog in
  Alcotest.(check bool) "closure called via apply_value" true (count is_apply_value m >= 1);
  Alcotest.(check bool) "reads via array_get" true (count (app_of "rt.array_get") m >= 1);
  Alcotest.(check bool) "builds a result array" true (count (app_of "rt.array_new") m >= 1);
  Alcotest.(check (list string)) "verifies" [] (Sil.verify m)

let test_filter_keeps_element () =
  let m = lower filterprog in
  Alcotest.(check bool) "predicate via apply_value" true (count is_apply_value m >= 1);
  Alcotest.(check (list string)) "verifies" [] (Sil.verify m)

let test_reduce_is_scalar () =
  (* reduce folds into an accumulator — NO result array is built (array_new only for the literal) *)
  let m = lower reduceprog in
  Alcotest.(check bool) "fold via apply_value" true (count is_apply_value m >= 1);
  Alcotest.(check int) "only the literal's array_new (none for the result)" 1
    (count (app_of "rt.array_new") m);
  Alcotest.(check (list string)) "verifies" [] (Sil.verify m)

let test_reject_bad_closure () =
  let _, d = front "let a = [1,2,3]\nlet b = a.filter({ (x: Int) -> Int in x })\nprint(b.count)" in
  Alcotest.(check bool) "filter closure must return Bool" true
    (List.exists (fun s -> String.length s >= 6 && String.sub s 0 6 = "filter") (msgs d))

let test_accepts_trio () =
  let _, d =
    front
      "let a = [1,2,3]\nlet b = a.map({ (x: Int) -> Int in x + 1 })\nlet c = b.filter({ (x: Int) \
       -> Bool in x > 1 })\nprint(c.reduce(0, { (s: Int, x: Int) -> Int in s + x }))"
  in
  Alcotest.(check bool) "chained trio accepted" false (Diagnostics.has_errors d)

let test_opt_safe () =
  let m = Opt.optimize (lower mapprog) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let () =
  Alcotest.run "collections"
    [
      ( "lowering",
        [
          Alcotest.test_case "map calls closure per element" `Quick test_map_calls_closure;
          Alcotest.test_case "filter keeps via predicate" `Quick test_filter_keeps_element;
          Alcotest.test_case "reduce folds to a scalar" `Quick test_reduce_is_scalar;
        ] );
      ( "typing",
        [
          Alcotest.test_case "bad closure rejected" `Quick test_reject_bad_closure;
          Alcotest.test_case "chained trio accepted" `Quick test_accepts_trio;
        ] );
      ("optimizer", [ Alcotest.test_case "-O safe" `Quick test_opt_safe ]);
    ]
