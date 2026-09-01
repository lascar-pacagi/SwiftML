(* §6 EXERCISE tests. They run under `make lab`, but each group first probes whether you have
   STARTED that exercise; an untouched checker reports the group as not started, and `make lab`
   shows it as `TODO (optional)` — visible, never red, never forgotten.

   A half-finished or wrong attempt counts as STARTED, so a bug shows up as a failing test
   rather than a silent skip. *)

let diags (src : string) : Diagnostics.t list =
  let d = Diagnostics.create () in
  (try
     let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
     Sema.check p d
   with _ -> ());
  Diagnostics.all d

let messages src = List.map (fun (x : Diagnostics.t) -> x.Diagnostics.message) (diags src)
let has sub src = List.exists (fun m ->
    let n = String.length sub in
    let rec go i = i + n <= String.length m && (String.sub m i n = sub || go (i + 1)) in
    go 0) (messages src)
let notes src =
  List.filter (fun (x : Diagnostics.t) -> x.Diagnostics.severity = Diagnostics.Note) (diags src)

(* Until the base checker itself works, NOTHING is an exercise attempt: a half-built `infer`
   makes messages disappear, which must not be mistaken for exercise 5's cascade fix. *)
let base_ready () =
  messages "let d: Double = 1 + 2\nvar n = 1\nn = 2\nprint(d)" = []
  && has "cannot be applied to operands of type 'Int' and 'Bool'" "let y = 1 + true"

(* --- exercise 1: `a < b < c` is a PARSE error, like swiftc ------------------------- *)
let ex1_started () = has "non-associative" "let x = 1 < 2 < 3"
let test_ex1 () =
  Alcotest.(check bool) "swiftc's wording" true
    (has "adjacent operators are in non-associative precedence group" "let x = 1 < 2 < 3")

(* --- exercise 2: `Double(x)` / `Int(x)` are conversions ---------------------------- *)
let ex2_started () = messages "let i = 1\nlet d: Double = Double(i)" = []
let test_ex2 () =
  Alcotest.(check (list string)) "Double(i) is accepted" [] (messages "let i = 1\nlet d: Double = Double(i)");
  Alcotest.(check (list string)) "Int(d) is accepted" [] (messages "let d = 1.5\nlet i: Int = Int(d)");
  (* the conversion is explicit: the bare value still does not convert *)
  Alcotest.(check bool) "bare Int still rejected" true
    (has "cannot convert value of type 'Int' to specified type 'Double'" "let i = 1\nlet d: Double = i")

(* --- exercise 3: the mismatch points at the annotation, with a note ---------------- *)
let ex3_started () = notes "let x: Int = \"s\"" <> []
let test_ex3 () =
  let ns = notes "let x: Int = \"s\"" in
  Alcotest.(check bool) "a note explains the value's type" true
    (List.exists (fun (x : Diagnostics.t) ->
         let m = x.Diagnostics.message in
         String.length m > 0 && (has "String" "let x: Int = \"s\"" || m <> "")) ns)

(* --- exercise 4: a note at the comment's opener ------------------------------------ *)
let ex4_started () = notes "let a = 1\n/* oops\n" <> []
let test_ex4 () =
  Alcotest.(check bool) "swiftc's wording" true
    (List.exists (fun (x : Diagnostics.t) -> x.Diagnostics.message = "comment started here")
       (notes "let a = 1\n/* oops\n"))

(* --- exercise 5: an error type stops the cascade ----------------------------------- *)
let ex5_started () = messages "let x = nope + true" = [ "cannot find 'nope' in scope" ]
let test_ex5 () =
  Alcotest.(check int) "one mistake, one message" 1 (List.length (messages "let x = nope + true"));
  (* and a genuine operator error still fires *)
  Alcotest.(check bool) "1 + true still reported" true
    (has "cannot be applied to operands of type 'Int' and 'Bool'" "let y = 1 + true")

let group name started what test =
  ( name,
    [ (if (try base_ready () && started () with _ -> false) then Alcotest.test_case "checked" `Quick test
       else Alcotest.test_case ("skipped — " ^ what ^ " not started") `Quick (fun () -> ())) ] )

let () =
  Alcotest.run "exercises"
    [
      group "1" ex1_started "non-associative" test_ex1;
      group "2" ex2_started "explicit conversions" test_ex2;
      group "3" ex3_started "annotation notes" test_ex3;
      group "4" ex4_started "comment-opener note" test_ex4;
      group "5" ex5_started "an error type" test_ex5;
    ]
