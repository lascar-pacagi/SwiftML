(* FROZEN SOLUTION — concept 04-codegen. Verified answer key for [irgen.ml].
   Kept out of the build by `(dirs :standard \ solution)`. Verify by copying over
   ../irgen.ml and running `dune build @phase1-minimal/04-codegen/runtest`.

   Phase-1 IRGen lowers the checked AST straight to LLVM IR *text* (no SIL yet; that
   arrives in Phase 2). A simple stack/value model: every binding gets an `alloca`,
   reads are `load`, writes are `store`. Phase 4's mem2reg promotes these to SSA.

   Design oracle: swift/lib/IRGen/* ; LLVM LangRef. We emit opaque-pointer IR (`ptr`),
   which Apple clang (LLVM 15+) consumes directly, and print via libc `printf`. *)

let emit_llvm (prog : Ast.program) : string =
  let buf = Buffer.create 256 in
  let next_reg = ref 0 in
  let fresh () =
    incr next_reg;
    Printf.sprintf "%%t%d" !next_reg
  in
  (* name -> the `alloca` pointer register holding that binding's slot. *)
  let slots : (string, string) Hashtbl.t = Hashtbl.create 16 in
  let slot_of (name : string) : string =
    match Hashtbl.find_opt slots name with
    | Some r -> r
    | None ->
        let r = Printf.sprintf "%%%s.addr" name in
        Buffer.add_string buf (Printf.sprintf "  %s = alloca i64\n" r);
        Hashtbl.add slots name r;
        r
  in
  (* Lower an expression; return the operand string (an i64 literal or a register). *)
  let rec gen_expr (e : Ast.expr) : string =
    match e with
    | Ast.Int_lit (n, _) -> string_of_int n
    | Ast.Var (x, _) ->
        let r = fresh () in
        Buffer.add_string buf (Printf.sprintf "  %s = load i64, ptr %s\n" r (slot_of x));
        r
    | Ast.Unary (Ast.Neg, e, _) ->
        let v = gen_expr e in
        let r = fresh () in
        Buffer.add_string buf (Printf.sprintf "  %s = sub i64 0, %s\n" r v);
        r
    | Ast.Binary (op, l, r0, _) ->
        let lv = gen_expr l in
        let rv = gen_expr r0 in
        let r = fresh () in
        let opcode =
          match op with
          | Ast.Add -> "add"
          | Ast.Sub -> "sub"
          | Ast.Mul -> "mul"
          | Ast.Div -> "sdiv" (* Phase 1: plain signed ops; trapping div/overflow is Phase 2 *)
          | Ast.Mod -> "srem"
        in
        Buffer.add_string buf (Printf.sprintf "  %s = %s i64 %s, %s\n" r opcode lv rv);
        r
    | Ast.Call (f, args, _) ->
        if f = "print" then (
          let v = match args with [ a ] -> gen_expr a | _ -> failwith "IRGen: print arity" in
          let r = fresh () in
          Buffer.add_string buf
            (Printf.sprintf "  %s = call i32 (ptr, ...) @printf(ptr @.fmt, i64 %s)\n" r v);
          (* print is Void in Swift; Phase 1 never uses its value. *)
          "0")
        else failwith (Printf.sprintf "IRGen: unsupported call to '%s'" f)
  in
  let gen_stmt (s : Ast.stmt) : unit =
    match s with
    | Ast.Let { name; value; _ } ->
        let addr = slot_of name in
        let v = gen_expr value in
        Buffer.add_string buf (Printf.sprintf "  store i64 %s, ptr %s\n" v addr)
    | Ast.Assign { name; value; _ } ->
        let addr = slot_of name in
        let v = gen_expr value in
        Buffer.add_string buf (Printf.sprintf "  store i64 %s, ptr %s\n" v addr)
    | Ast.Expr_stmt (e, _) -> ignore (gen_expr e)
  in
  List.iter gen_stmt prog.Ast.stmts;
  let body = Buffer.contents buf in
  (* No target triple/datalayout on purpose — the driver passes -Wno-override-module
     and clang fills in the host triple. *)
  String.concat ""
    [
      "; swiftml Phase-1 LLVM IR\n";
      "@.fmt = private unnamed_addr constant [6 x i8] c\"%lld\\0A\\00\"\n\n";
      "declare i32 @printf(ptr, ...)\n\n";
      "define i32 @main() {\n";
      "entry:\n";
      body;
      "  ret i32 0\n";
      "}\n";
    ]
