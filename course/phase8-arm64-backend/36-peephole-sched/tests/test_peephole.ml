(* Alcotest unit tests for concept-36: local redundant-load elimination (peephole). *)
open Arm64

let pp instrs = Peephole.peephole instrs

(* store then reload SAME register from SAME slot -> the load disappears *)
let test_store_reload_same () =
  let got = pp [ Str (X 19, SP, 24); Ldr (X 19, SP, 24); Ret ] in
  Alcotest.(check (list string)) "reload of same reg dropped"
    [ "\tstr\tx19, [sp, #24]"; "\tret" ]
    (List.map string_of_instr got)

(* store then reload into a DIFFERENT register -> the load becomes a register move *)
let test_store_reload_other () =
  let got = pp [ Str (X 19, SP, 24); Ldr (X 20, SP, 24); Ret ] in
  Alcotest.(check (list string)) "reload forwarded to a mov"
    [ "\tstr\tx19, [sp, #24]"; "\tmov\tx20, x19"; "\tret" ]
    (List.map string_of_instr got)

(* a move to self is dropped *)
let test_mov_self () =
  Alcotest.(check (list string)) "mov self dropped" [ "\tret" ]
    (List.map string_of_instr (pp [ Mov (X 19, R (X 19)); Ret ]))

(* a write to the holding register invalidates forwarding (correctness over cleverness) *)
let test_invalidation () =
  let got = pp [ Str (X 19, SP, 24); Mov (X 19, Imm 5); Ldr (X 20, SP, 24); Ret ] in
  (* x19 was clobbered, so the reload must STAY a load (not `mov x20, x19`) *)
  Alcotest.(check bool) "reload kept after holder clobbered" true
    (List.exists (function Ldr (X 20, SP, 24) -> true | _ -> false) got)

(* a call clobbers broadly, so the table is dropped at a `bl` *)
let test_call_resets () =
  let got = pp [ Str (X 19, SP, 24); Bl "_f"; Ldr (X 20, SP, 24); Ret ] in
  Alcotest.(check bool) "reload kept across a call" true
    (List.exists (function Ldr (X 20, SP, 24) -> true | _ -> false) got)

(* two loads of the SAME slot: the second is forwarded from the first's destination *)
let test_load_load () =
  let got = pp [ Ldr (X 19, SP, 24); Ldr (X 20, SP, 24); Ret ] in
  Alcotest.(check (list string)) "second load forwarded"
    [ "\tldr\tx19, [sp, #24]"; "\tmov\tx20, x19"; "\tret" ]
    (List.map string_of_instr got)

(* a store to a DIFFERENT slot leaves the first slot's entry alone (memory, not a register) *)
let test_other_slot_kept () =
  let got = pp [ Str (X 19, SP, 24); Str (X 21, SP, 32); Ldr (X 20, SP, 24); Ret ] in
  Alcotest.(check bool) "unrelated store does not invalidate" true
    (List.exists (function Mov (X 20, R (X 19)) -> true | _ -> false) got)

(* a label boundary resets the table — no cross-block forwarding *)
let test_block_boundary () =
  let got = pp [ Str (X 19, SP, 24); Label "L1"; Ldr (X 20, SP, 24); Ret ] in
  Alcotest.(check bool) "no forwarding across a label" true
    (List.exists (function Ldr (X 20, SP, 24) -> true | _ -> false) got)

(* on a real program, peephole reduces memory loads while preserving the load/store of true new
   values; and never introduces a virtual register *)
let backend src =
  let d = Diagnostics.create () in
  let p = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d) in
  Sema.check p d;
  let funcs, _ = Isel.select (Silgen.lower p) in
  List.map (fun f -> Regalloc.run Regalloc.Graphcolor f) funcs

let count_ldr fs = List.fold_left (fun a (f : Arm64.func) -> a + List.length (List.filter (function Ldr _ -> true | _ -> false) f.Arm64.instrs)) 0 fs

let test_reduces_loads () =
  let src = "let a = 7\nlet b = 11\nprint(a*a + a*b + b*b + a + b)" in
  let fs = backend src in
  let before = count_ldr fs in
  let after = count_ldr (List.map Peephole.optimize fs) in
  Alcotest.(check bool) "peephole reduces memory loads" true (after < before)

let () =
  Alcotest.run "peephole"
    [
      ( "rules",
        [
          Alcotest.test_case "store/reload same reg -> drop" `Quick test_store_reload_same;
          Alcotest.test_case "store/reload other reg -> mov" `Quick test_store_reload_other;
          Alcotest.test_case "load/load -> mov" `Quick test_load_load;
          Alcotest.test_case "mov self -> drop" `Quick test_mov_self;
        ] );
      ( "soundness",
        [
          Alcotest.test_case "clobber invalidates" `Quick test_invalidation;
          Alcotest.test_case "a call resets the table" `Quick test_call_resets;
          Alcotest.test_case "other slot not invalidated" `Quick test_other_slot_kept;
          Alcotest.test_case "no cross-block forwarding" `Quick test_block_boundary;
        ] );
      ("effect", [ Alcotest.test_case "reduces memory loads" `Quick test_reduces_loads ]);
    ]
