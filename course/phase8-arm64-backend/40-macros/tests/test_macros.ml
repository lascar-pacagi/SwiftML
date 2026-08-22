(* Alcotest unit tests for concept-40: the compile-time macro expander. *)
let parse (src : string) : Ast.program =
  let d = Diagnostics.create () in
  Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src d)) d)

let expand src = Macros.expand_program (parse src)

(* find any expression in the expanded program, to confirm a macro disappeared *)
let rec has_macro_expr = function
  | Ast.MacroExpr _ -> true
  | Ast.Unary (_, a, _) | Ast.Force_unwrap (a, _) | Ast.Cast (a, _, _, _) | Ast.Try (_, a, _)
  | Ast.Await (a, _) | Ast.Member (a, _, _) -> has_macro_expr a
  | Ast.Binary (_, a, b, _) | Ast.Coalesce (a, b, _) | Ast.Subscript (a, b, _) -> has_macro_expr a || has_macro_expr b
  | Ast.Call (_, args, _) -> List.exists (fun (_, a) -> has_macro_expr a) args
  | Ast.Method_call (r, _, args, _) -> has_macro_expr r || List.exists (fun (_, a) -> has_macro_expr a) args
  | Ast.Array_lit (es, _) -> List.exists has_macro_expr es
  | Ast.Closure (_, _, b, _) -> has_macro_expr b
  | _ -> false

let top_exprs (p : Ast.program) : Ast.expr list =
  List.filter_map (function Ast.IStmt (Ast.Expr_stmt (e, _)) | Ast.IStmt (Ast.Let { value = e; _ }) -> Some e | _ -> None) p.Ast.items

let test_line_becomes_literal () =
  (* `#line` on the first source line expands to the integer literal 1 *)
  let p = expand "let x = #line" in
  match top_exprs p with
  | [ Ast.Int_lit (1, _) ] -> ()
  | _ -> Alcotest.fail "#line did not expand to the integer 1"

let test_no_macro_survives () =
  let p = expand "print(#line + 5)\nlet y = #column" in
  Alcotest.(check bool) "no MacroExpr left after expansion" false
    (List.exists (function Ast.IStmt s -> (match s with Ast.Expr_stmt (e, _) -> has_macro_expr e | Ast.Let { value; _ } -> has_macro_expr value | _ -> false) | _ -> false) p.Ast.items)

let test_assert_becomes_if () =
  (* `#assert(c)` as a statement expands to an `if c { } else { fatalError() }` *)
  let p = expand "let x = 1\n#assert(x > 0)" in
  let is_if_with_fatal = function
    | Ast.IStmt (Ast.If { else_blk = Some [ Ast.Expr_stmt (Ast.Call ("fatalError", _, _), _) ]; _ }) -> true
    | _ -> false
  in
  Alcotest.(check bool) "#assert expanded to if/else-fatalError" true (List.exists is_if_with_fatal p.Ast.items)

let test_unknown_macro_rejected () =
  (* an unknown macro survives expansion and the type checker rejects it *)
  let d = Diagnostics.create () in
  let prog = Macros.expand_program (parse "print(#bogus)") in
  Sema.check prog d;
  Alcotest.(check bool) "unknown macro rejected" true
    (List.exists (fun (e : Diagnostics.t) -> e.Diagnostics.message = "unknown macro '#bogus'") d.Diagnostics.diags)

let () =
  Alcotest.run "macros"
    [
      ( "expansion",
        [
          Alcotest.test_case "#line -> integer literal" `Quick test_line_becomes_literal;
          Alcotest.test_case "no macro survives" `Quick test_no_macro_survives;
          Alcotest.test_case "#assert -> if/fatalError" `Quick test_assert_becomes_if;
        ] );
      ("diagnostics", [ Alcotest.test_case "unknown macro rejected" `Quick test_unknown_macro_rejected ]);
    ]
