(* Alcotest unit tests for concept-31: Array/String lowering + copy-on-write + the v0 scope. *)
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

(* the STORE-BACK: every make_unique's result must be stored into the slot it came from, or the
   copy is written to and then thrown away — the classic copy-on-write bug *)
let test_store_back () =
  let m = lower cow in
  let f = List.find (fun (fn : Sil.func) -> fn.Sil.fname = "main") m.Sil.funcs in
  (* blocks and instructions are both accumulated by prepending, so both need reversing to
     read them in program order — and order is exactly what this test is about *)
  let seq = List.concat_map (fun (b : Sil.block) -> List.rev b.Sil.instrs) (List.rev f.Sil.blocks) in
  (* walk the instruction stream: each apply of make_unique defines a value, and that value must
     appear as the SOURCE of a later Store *)
  let uniq_results =
    let fr = ref [] in
    List.filter_map
      (fun (v, i) ->
        match i with
        | Sil.Func_ref "rt.array_make_unique" -> fr := v :: !fr; None
        | Sil.Apply (callee, _) when List.mem callee !fr -> Some v
        | _ -> None)
      seq
  in
  Alcotest.(check int) "two make_unique results" 2 (List.length uniq_results);
  List.iter
    (fun r ->
      Alcotest.(check bool) "its result is stored back" true
        (List.exists (function _, Sil.Store (src, _) -> src = r | _ -> false) seq))
    uniq_results

let test_multiline_literal () =
  (* a newline inside brackets separates nothing; the lexer drops it while the depth is > 0 *)
  let d = Diagnostics.create () in
  let toks = Lexer.tokenize (Lexer.create "let a = [\n  1,\n  2\n]\nprint(a.count)" d) in
  Alcotest.(check bool) "no newline inside the brackets" true
    (let rec scan depth = function
       | [] -> true
       | (t : Token.t) :: r -> (
           match t.Token.kind with
           | Token.LBracket -> scan (depth + 1) r
           | Token.RBracket -> scan (depth - 1) r
           | Token.Newline when depth > 0 -> false
           | _ -> scan depth r)
     in
     scan 0 toks);
  let _, d2 = front "let a = [\n  1,\n  2\n]\nprint(a.count)" in
  Alcotest.(check bool) "and it type-checks" false (Diagnostics.has_errors d2)

let test_let_array_rules () =
  (* `append` mutates, so it needs a `var` — swiftc's rule, and ours since it was checked *)
  Alcotest.(check bool) "append on a let rejected" true
    (Diagnostics.has_errors (snd (front "let a = [1, 2]\na.append(3)")));
  Alcotest.(check bool) "subscript-set on a let rejected" true
    (Diagnostics.has_errors (snd (front "let a = [1, 2]\na[0] = 5")));
  Alcotest.(check bool) "on a var, both fine" false
    (Diagnostics.has_errors (snd (front "var a = [1, 2]\na.append(3)\na[0] = 5\nprint(a.count)")))

let test_aggregate_divergence () =
  (* the two places we are SMALLER than Swift: no aggregate print, no aggregate compare *)
  Alcotest.(check bool) "print of an array rejected" true
    (Diagnostics.has_errors (snd (front "let a = [1, 2]\nprint(a)")));
  Alcotest.(check bool) "== on two arrays rejected" true
    (Diagnostics.has_errors (snd (front "let a = [1, 2]\nlet b = [1, 2]\nprint(a == b)")))

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
          Alcotest.test_case "unique pointer stored back" `Quick test_store_back;
        ] );
      ( "scope",
        [
          Alcotest.test_case "[String] rejected" `Quick test_reject_string_array;
          Alcotest.test_case "[Int] accepted" `Quick test_accept_int_array;
          Alcotest.test_case "mutating a let array" `Quick test_let_array_rules;
          Alcotest.test_case "no aggregate print or ==" `Quick test_aggregate_divergence;
        ] );
      ("lexer", [ Alcotest.test_case "multi-line literal" `Quick test_multiline_literal ]);
      ("optimizer", [ Alcotest.test_case "-O safe" `Quick test_opt_safe ]);
    ]
