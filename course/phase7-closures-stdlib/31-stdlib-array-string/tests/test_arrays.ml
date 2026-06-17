(* Alcotest unit tests for concept-31: Array/String lowering + copy-on-write + the v0 scope. *)
let front (src : string) =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src)) d) in
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

(* a literal + count + subscript + concat program exercises every runtime intrinsic *)
let mixed = "var a = [10, 20, 30]\nprint(a.count)\nprint(a[0])\nvar s = \"hi\"\nprint(s.count)\nlet t = s + \"!\"\nprint(t)"

let test_literal_desugar () =
  (* `[10,20,30]` lowers to one array_new + one push per element — no new SIL instruction kinds *)
  let m = lower mixed in
  Alcotest.(check int) "one array_new" 1 (count (app_of "rt.array_new") m);
  Alcotest.(check int) "three pushes" 3 (count (app_of "rt.array_push") m);
  Alcotest.(check bool) "subscript -> array_get" true (count (app_of "rt.array_get") m >= 1);
  Alcotest.(check bool) "count -> array_count" true (count (app_of "rt.array_count") m >= 1);
  Alcotest.(check (list string)) "verifies" [] (Sil.verify m)

let test_string_desugar () =
  (* `s + "!"` is a runtime concat; `s.count` is a runtime length — Strings are C-strings *)
  let m = lower mixed in
  Alcotest.(check int) "one str_concat" 1 (count (app_of "rt.str_concat") m);
  Alcotest.(check int) "one str_count" 1 (count (app_of "rt.str_count") m)

(* copy-on-write: a SHARE (`var b = a`) retains; a MUTATION (`append`/`a[i]=`) makes unique *)
let cow = "var a = [1, 2, 3]\nvar b = a\nb.append(4)\nb[0] = 9\nprint(a.count)\nprint(b.count)"

let test_cow_dance () =
  let m = lower cow in
  (* `var b = a` shares the buffer => exactly one retain *)
  Alcotest.(check int) "share -> one retain" 1 (count (app_of "rt.array_retain") m);
  (* the two mutations each make the buffer unique before writing *)
  Alcotest.(check int) "two mutations -> two make_unique" 2 (count (app_of "rt.array_make_unique") m);
  Alcotest.(check (list string)) "verifies" [] (Sil.verify m)

let test_fresh_literal_no_retain () =
  (* a fresh literal already owns its buffer (+1) — binding it needs NO retain *)
  let m = lower "var a = [1, 2]\nprint(a.count)" in
  Alcotest.(check int) "fresh literal -> zero retains" 0 (count (app_of "rt.array_retain") m)

let test_reject_string_array () =
  let _, d = front "let xs = [\"a\", \"b\"]\nprint(xs.count)" in
  Alcotest.(check bool) "[String] rejected" true
    (List.exists (fun s -> String.length s >= 9 && String.sub s 0 9 = "arrays of") (msgs d))

let test_accept_int_array () =
  let _, d = front "var a = [1, 2, 3]\na.append(4)\na[0] = 9\nfor x in a { print(x) }\nlet e: [Int] = []\nprint(e.isEmpty)" in
  Alcotest.(check bool) "[Int] program accepted" false (Diagnostics.has_errors d)

let test_opt_safe () =
  let m = Opt.optimize (lower cow) in
  Alcotest.(check (list string)) "valid after -O" [] (Sil.verify m)

let () =
  Alcotest.run "arrays"
    [
      ( "lowering",
        [
          Alcotest.test_case "array literal desugar" `Quick test_literal_desugar;
          Alcotest.test_case "string desugar" `Quick test_string_desugar;
        ] );
      ( "copy-on-write",
        [
          Alcotest.test_case "share retains, mutate make_unique" `Quick test_cow_dance;
          Alcotest.test_case "fresh literal no retain" `Quick test_fresh_literal_no_retain;
        ] );
      ( "scope",
        [
          Alcotest.test_case "[String] rejected" `Quick test_reject_string_array;
          Alcotest.test_case "[Int] accepted" `Quick test_accept_int_array;
        ] );
      ("optimizer", [ Alcotest.test_case "-O safe" `Quick test_opt_safe ]);
    ]
