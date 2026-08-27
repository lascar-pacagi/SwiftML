(* Semantic analysis: name resolution + (trivial) type checking for the Phase-1 subset.

   Phase 1 is trivial — the only type is Int — so this mostly checks name resolution:
   every variable is declared before use, assignment targets exist and are mutable,
   and print(_:) is called with one argument. Grows into a real bidirectional checker
   (Phase 2) and toward the constraint solver (Phase 5).

   >>> You build this in concept  phase1-minimal/03-sema. <<<

   Design oracle:
     swift/lib/Sema/TypeCheckDecl.cpp  TypeCheckExpr.cpp  TypeCheckStmt.cpp *)

(* The Phase-1 type lattice: just Int. (Grows: Bool, Double, String, … in Phase 2.) *)
type ty = TInt

let string_of_ty = function TInt -> "Int"

(* Walk the program, resolving names and (trivially) type-checking, reporting into
   [diags] — the driver bails before IRGen if [Diagnostics.has_errors].

   Two rules are easy to get subtly wrong, and the tests pin both: an initializer is
   checked BEFORE its name is bound, and an assignment target must be declared AND
   mutable. Every diagnostic is compared against swiftc's wording.
   Walk-through: explainer §3. *)
let check (prog : Ast.program) (diags : Diagnostics.sink) : unit =
  let env = Hashtbl.create 16 in
  let rec check_expr e = 
    match e with
    | Ast.Int_lit _ -> TInt
    | Ast.Var (x, span) -> begin
      try 
        let ty, _, _ = Hashtbl.find env x in ty
      with Not_found ->
        Diagnostics.error diags span 
          (Printf.sprintf "cannot find '%s' in scope" x);
        TInt 
    end
    | Ast.Unary (_, e', _) -> ignore (check_expr e'); TInt
    | Ast.Binary (_, e1, e2, _) -> begin 
      ignore (check_expr e1);
      ignore (check_expr e2);
      TInt
    end
    | Ast.Call ("print", args, span) -> begin
      if List.length args <> 1 then
        Diagnostics.error diags span
          "print(_:) expects exactly one argument";
      List.iter (fun e -> ignore (check_expr e)) args;
      TInt
    end
    | Ast.Call (f, args, span) -> begin
      Diagnostics.error diags span
          (Printf.sprintf "cannot find '%s' in scope" f);
      List.iter (fun e -> ignore (check_expr e)) args;
      TInt
    end  
  in
  let check_instr ins =
    match ins with 
    | Ast.Let { name; is_var; value; span } -> begin
      let ty = check_expr value in
      match Hashtbl.find_opt env name with
      | Some (_, _, span') -> begin
        Diagnostics.error diags span
          (Printf.sprintf "invalid redeclaration of '%s'" name);
        Diagnostics.note diags span'
          (Printf.sprintf "'%s' previously declared here" name)
      end
      | None -> Hashtbl.add env name (ty, is_var, span)
    end
    | Ast.Assign { name; value; span } -> begin
      ignore (check_expr value);
      try
        let _, is_var, span' = Hashtbl.find env name in        
        if not is_var then begin
          Diagnostics.error diags span
            (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant" name);
          Diagnostics.note diags span' "change 'let' to 'var' to make it mutable"
        end
      with Not_found ->
        Diagnostics.error diags span
          (Printf.sprintf "cannot find '%s' in scope" name)
    end
    | Ast.Expr_stmt (e, _) -> ignore (check_expr e) 
  in
  List.iter check_instr prog.stmts
  (* ignore (prog, diags, string_of_ty);
  failwith "TODO(03-sema): implement Sema.check (scope + name resolution + Int typing)" *)
