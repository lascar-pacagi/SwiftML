(* FROZEN SOLUTION — concept 04-codegen. Verified answer key for [irgen.ml].
   Kept out of the build by `(dirs :standard \ solution)`. Verify by copying over
   ../irgen.ml and running `dune build @phase1-minimal/04-codegen/runtest`.

   Phase-1 IRGen lowers the checked AST straight to LLVM IR *text* (no SIL yet; that
   arrives in Phase 2). A simple stack/value model: every binding gets an `alloca`,
   reads are `load`, writes are `store`. Phase 4's mem2reg promotes these to SSA.

   Design oracle: swift/lib/IRGen/* ; LLVM LangRef. We emit opaque-pointer IR (`ptr`),
   which Apple clang (LLVM 15+) consumes directly, and print via libc `printf`. *)

(* The state the lowering shares. swiftc bundles the same three things in
   `IRGenFunction` (IRGenFunction.h:77): somewhere to put instructions, a way to name
   values, and the map from source names to their storage. *)
type ctx = {
  buf : Buffer.t; (* the instructions of `main`, in order *)
  mutable next_reg : int; (* how many %tN names have been handed out *)
  slots : (string, string) Hashtbl.t; (* source name -> the alloca register holding it *)
}

let create () : ctx = { buf = Buffer.create 256; next_reg = 0; slots = Hashtbl.create 16 }

(* append one instruction, indented like the body of a function *)
let emit (c : ctx) (line : string) : unit = Buffer.add_string c.buf ("  " ^ line ^ "\n")

(* a register name nobody has used yet: %t1, %t2, … ("%%" is a literal '%') *)
let fresh (c : ctx) : string =
  c.next_reg <- c.next_reg + 1;
  Printf.sprintf "%%t%d" c.next_reg

(* The slot a name lives in — the register `alloca` returned. First use emits the
   `alloca`; later uses find the same register, so a reassigned `var` stores into its
   existing slot instead of allocating a second one. *)
let slot_of (c : ctx) (name : string) : string =
  match Hashtbl.find_opt c.slots name with
  | Some r -> r
  | None ->
      let r = Printf.sprintf "%%%s.addr" name in
      emit c (Printf.sprintf "%s = alloca i64" r);
      Hashtbl.add c.slots name r;
      r

(* Lower an expression: emit its instructions, return the operand holding its result —
   an immediate like "42", or a register like "%t3". *)
let rec emit_expr (c : ctx) (e : Ast.expr) : string =
  match e with
  | Ast.Int_lit (n, _) -> string_of_int n
  | Ast.Var (x, _) ->
      let r = fresh c in
      emit c (Printf.sprintf "%s = load i64, ptr %s" r (slot_of c x));
      r
  | Ast.Unary (Ast.Neg, e, _) ->
      let v = emit_expr c e in
      let r = fresh c in
      emit c (Printf.sprintf "%s = sub i64 0, %s" r v);
      r
  | Ast.Binary (op, l, r0, _) ->
      let lv = emit_expr c l in
      let rv = emit_expr c r0 in
      let r = fresh c in
      let opcode =
        match op with
        | Ast.Add -> "add"
        | Ast.Sub -> "sub"
        | Ast.Mul -> "mul"
        (* Phase 1: plain signed ops; trapping div/overflow is Phase 2 *)
        | Ast.Div -> "sdiv"
        | Ast.Mod -> "srem"
      in
      emit c (Printf.sprintf "%s = %s i64 %s, %s" r opcode lv rv);
      r
  | Ast.Call (f, args, _) ->
      if f = "print" then (
        let v =
          match args with [ a ] -> emit_expr c a | _ -> failwith "IRGen: print arity"
        in
        let r = fresh c in
        emit c (Printf.sprintf "%s = call i32 (ptr, ...) @printf(ptr @.fmt, i64 %s)" r v);
        (* print is Void in Swift; Phase 1 never uses its value. *)
        "0")
      else failwith (Printf.sprintf "IRGen: unsupported call to '%s'" f)

(* Lower a statement. Declarations and assignments both end in a store to the name's
   slot; a bare expression is emitted for its instructions and its operand dropped. *)
let emit_stmt (c : ctx) (s : Ast.stmt) : unit =
  match s with
  | Ast.Let { name; value; _ } ->
      let addr = slot_of c name in
      let v = emit_expr c value in
      emit c (Printf.sprintf "store i64 %s, ptr %s" v addr)
  | Ast.Assign { name; value; _ } ->
      let addr = slot_of c name in
      let v = emit_expr c value in
      emit c (Printf.sprintf "store i64 %s, ptr %s" v addr)
  | Ast.Expr_stmt (e, _) -> ignore (emit_expr c e)

(* The whole module: the preamble, one `define i32 @main`, the statements in order.
   No target triple/datalayout on purpose — the driver passes -Wno-override-module and
   clang fills in the host triple. *)
let emit_llvm (prog : Ast.program) : string =
  let c = create () in
  List.iter (emit_stmt c) prog.Ast.stmts;
  String.concat ""
    [
      "; swiftml Phase-1 LLVM IR\n";
      "@.fmt = private unnamed_addr constant [6 x i8] c\"%lld\\0A\\00\"\n\n";
      "declare i32 @printf(ptr, ...)\n\n";
      "define i32 @main() {\n";
      "entry:\n";
      Buffer.contents c.buf;
      "  ret i32 0\n";
      "}\n";
    ]
