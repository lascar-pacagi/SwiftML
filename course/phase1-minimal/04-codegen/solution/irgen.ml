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
type context = {
  buffer : Buffer.t; (* the instructions of `main`, in order *)
  mutable next_register : int; (* how many %tN names have been handed out *)
  slots : (string, string) Hashtbl.t; (* source name -> the alloca register holding it *)
}

let create () : context = { buffer = Buffer.create 256; next_register = 0; slots = Hashtbl.create 16 }

(* append one instruction, indented like the body of a function *)
let emit (context : context) (line : string) : unit = Buffer.add_string context.buffer ("  " ^ line ^ "\n")

(* a register name nobody has used yet: %t1, %t2, … ("%%" is a literal '%') *)
let fresh (context : context) : string =
  context.next_register <- context.next_register + 1;
  Printf.sprintf "%%t%d" context.next_register

(* The slot a name lives in — the register `alloca` returned. First use emits the
   `alloca`; later uses find the same register, so a reassigned `var` stores into its
   existing slot instead of allocating a second one. *)
let slot_of (context : context) (name : string) : string =
  match Hashtbl.find_opt context.slots name with
  | Some slot -> slot
  | None ->
      let slot = Printf.sprintf "%%%s.addr" name in
      emit context (Printf.sprintf "%s = alloca i64" slot);
      Hashtbl.add context.slots name slot;
      slot

(* Lower an expression: emit its instructions, return the operand holding its result —
   an immediate like "42", or a register like "%t3". *)
let rec emit_expr (context : context) (expression : Ast.expr) : string =
  match expression with
  | Ast.Int_lit (value, _) -> string_of_int value
  | Ast.Var (name, _) ->
      let result_register = fresh context in
      emit context
        (Printf.sprintf "%s = load i64, ptr %s" result_register (slot_of context name));
      result_register
  | Ast.Unary (Ast.Neg, operand, _) ->
      let operand_value = emit_expr context operand in
      let result_register = fresh context in
      emit context (Printf.sprintf "%s = sub i64 0, %s" result_register operand_value);
      result_register
  | Ast.Binary (operator, left, right, _) ->
      let left_operand = emit_expr context left in
      let right_operand = emit_expr context right in
      let result_register = fresh context in
      let opcode =
        match operator with
        | Ast.Add -> "add"
        | Ast.Sub -> "sub"
        | Ast.Mul -> "mul"
        (* Phase 1: plain signed ops; trapping div/overflow is Phase 2 *)
        | Ast.Div -> "sdiv"
        | Ast.Mod -> "srem"
      in
      emit context
        (Printf.sprintf "%s = %s i64 %s, %s" result_register opcode left_operand right_operand);
      result_register
  | Ast.Call (callee, arguments, _) ->
      if callee = "print" then (
        let argument_operand =
          match arguments with
          | [ argument ] -> emit_expr context argument
          | _ -> failwith "IRGen: print arity"
        in
        let result_register = fresh context in
        emit context
          (Printf.sprintf "%s = call i32 (ptr, ...) @printf(ptr @.fmt, i64 %s)"
             result_register argument_operand);
        (* print is Void in Swift; Phase 1 never uses its value. *)
        "0")
      else failwith (Printf.sprintf "IRGen: unsupported call to '%s'" callee)

(* Lower a statement. Declarations and assignments both end in a store to the name's
   slot; a bare expression is emitted for its instructions and its operand dropped. *)
let emit_stmt (context : context) (statement : Ast.stmt) : unit =
  match statement with
  | Ast.Let { name; value; _ } ->
      let slot = slot_of context name in
      let value_operand = emit_expr context value in
      emit context (Printf.sprintf "store i64 %s, ptr %s" value_operand slot)
  | Ast.Assign { name; value; _ } ->
      let slot = slot_of context name in
      let value_operand = emit_expr context value in
      emit context (Printf.sprintf "store i64 %s, ptr %s" value_operand slot)
  | Ast.Expr_stmt (expression, _) -> ignore (emit_expr context expression)

(* The whole module: the preamble, one `define i32 @main`, the statements in order.
   No target triple/datalayout on purpose — the driver passes -Wno-override-module and
   clang fills in the host triple. *)
let emit_llvm (program : Ast.program) : string =
  let context = create () in
  List.iter (emit_stmt context) program.Ast.stmts;
  String.concat ""
    [
      "; swiftml Phase-1 LLVM IR\n";
      "@.fmt = private unnamed_addr constant [6 x i8] c\"%lld\\0A\\00\"\n\n";
      "declare i32 @printf(ptr, ...)\n\n";
      "define i32 @main() {\n";
      "entry:\n";
      Buffer.contents context.buffer;
      "  ret i32 0\n";
      "}\n";
    ]
