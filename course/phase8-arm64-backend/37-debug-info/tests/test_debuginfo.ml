(* Alcotest unit tests for concept-37: source-line debug info (.loc / DWARF line table). *)
let asm (src : string) : Arm64.func list =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  Alcotest.(check bool) "no sema errors" false (Diagnostics.has_errors d);
  fst (Isel.select (Silgen.lower p))

let locs m = List.concat_map (fun (f : Arm64.func) -> List.filter_map (function Arm64.Loc n -> Some n | _ -> None) f.Arm64.instrs) m

(* a 4-line program: each statement should produce a .loc for its line *)
let prog = "let a = 1\nlet b = 2\nlet c = a + b\nprint(c)"

let test_loc_per_line () =
  let ls = locs (asm prog) in
  (* lines 1..4 should all appear among the emitted .loc directives *)
  List.iter
    (fun n -> Alcotest.(check bool) (Printf.sprintf "line %d has a .loc" n) true (List.mem n ls))
    [ 1; 2; 3; 4 ]

let test_loc_monotone_and_deduped () =
  (* consecutive instructions from the SAME statement share one .loc — so no two ADJACENT
     .loc directives carry the same line *)
  let ls = locs (asm prog) in
  let rec no_adjacent_dup = function a :: b :: _ when a = b -> false | _ :: r -> no_adjacent_dup r | [] -> true in
  Alcotest.(check bool) "no adjacent duplicate .loc" true (no_adjacent_dup ls)

let test_lines_threaded_through_sil () =
  (* SILGen stamps each value with its source line; a value defined on line 3 reports line 3 *)
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create prog d)) d) in
  let m = Silgen.lower p in
  let f = List.hd m.Sil.funcs in
  let any_line_3 = Hashtbl.fold (fun _ l acc -> acc || l = 3) f.Sil.lines false in
  Alcotest.(check bool) "SIL carries a value from line 3" true any_line_3

let test_loc_in_printed_asm () =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create prog d)) d) in
  Sema.check p d;
  let funcs, cstrings = Isel.select (Silgen.lower p) in
  let s = Arm64.string_of_module (Regalloc.run_module ~source:"prog.swift" Regalloc.Graphcolor funcs cstrings) in
  let contains hay needle =
    let nh = String.length hay and nn = String.length needle in
    let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
    go 0
  in
  Alcotest.(check bool) "the .file directive is emitted" true (contains s ".file\t1 \"prog.swift\"");
  Alcotest.(check bool) "a .loc directive is emitted" true (contains s "\t.loc\t1 ")

let () =
  Alcotest.run "debuginfo"
    [
      ( "line table",
        [
          Alcotest.test_case "a .loc per source line" `Quick test_loc_per_line;
          Alcotest.test_case "deduped (shared per statement)" `Quick test_loc_monotone_and_deduped;
        ] );
      ( "threading",
        [
          Alcotest.test_case "SILGen stamps lines" `Quick test_lines_threaded_through_sil;
          Alcotest.test_case ".file + .loc in asm" `Quick test_loc_in_printed_asm;
        ] );
    ]
