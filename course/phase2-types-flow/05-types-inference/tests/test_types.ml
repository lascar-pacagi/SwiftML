(* Alcotest unit tests for the concept-05 type vocabulary (`types.ml`). `of_name` is a pure
   function, so it is tested by calling it — no lexer, parser or sema involved. That matters
   here: it is the one hole a learner can finish and verify before writing the checker.

   RED until the TODO(05) rows are filled; GREEN against solution/types.ml. *)

let ty = Alcotest.testable (fun fmt t -> Format.pp_print_string fmt (Types.string_of_ty t)) Types.equal

let test_known () =
  let same name expected =
    Alcotest.(check (option ty)) (Printf.sprintf "of_name %S" name) (Some expected)
      (Types.of_name name)
  in
  same "Int" Types.TInt;
  same "Bool" Types.TBool;
  same "Double" Types.TDouble;
  same "String" Types.TString

let test_unknown () =
  let none name =
    Alcotest.(check (option ty)) (Printf.sprintf "of_name %S" name) None (Types.of_name name)
  in
  none "Foo";
  (* case matters: Swift's type names are capitalised, `int` is not `Int` *)
  none "int";
  none "double";
  (* honest gap: `Float` is a real Swift type (32-bit); this subset has only Double *)
  none "Float";
  none ""

(* The annotation the user wrote and the type we print in a diagnostic must be the same
   spelling, or "cannot convert value of type 'X' to specified type 'Y'" would name a type
   nobody can write. *)
let test_round_trip () =
  List.iter
    (fun name ->
      match Types.of_name name with
      | Some t -> Alcotest.(check string) "round-trip" name (Types.string_of_ty t)
      | None -> Alcotest.failf "of_name %S returned None" name)
    [ "Int"; "Bool"; "Double"; "String" ]

let () =
  Alcotest.run "types"
    [
      ("of_name", [ Alcotest.test_case "the four type names" `Quick test_known ]);
      ("unknown", [ Alcotest.test_case "anything else is None" `Quick test_unknown ]);
      ("spelling", [ Alcotest.test_case "string_of_ty inverts of_name" `Quick test_round_trip ]);
    ]
