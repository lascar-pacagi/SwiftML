(* FROZEN SOLUTION — concept 04-codegen, WITH §6's EXERCISES APPLIED.
   Kept out of the build by `(dirs :standard \ solution)`. Run it with
   `make check-exercises C=phase1-minimal/04-codegen`.

   This is `solution/irgen.ml` plus exercise 1 (a slot only for names that are actually
   assigned) and exercise 2 (fold constant arithmetic). Read the stock answer key first:
   the differences are marked EX1 and EX2 below. Everything else is unchanged.

   Design oracle: swift/lib/IRGen/* ; LLVM LangRef. *)

type context = {
  buffer : Buffer.t; (* the instructions of `main`, in order *)
  mutable next_register : int; (* how many %tN names have been handed out *)
  slots : (string, string) Hashtbl.t;
      (* source name -> the alloca register holding it *)
  reassigned : (string, unit) Hashtbl.t;
      (* EX1: names that appear as an assignment target somewhere in the program *)
  values : (string, string) Hashtbl.t;
      (* EX1: source name -> its operand, for the names that need no slot *)
}

let create () : context =
  {
    buffer = Buffer.create 256;
    next_register = 0;
    slots = Hashtbl.create 16;
    reassigned = Hashtbl.create 16;
    values = Hashtbl.create 16;
  }

(* append one instruction, indented like the body of a function *)
let emit (context : context) (line : string) : unit =
  Buffer.add_string context.buffer ("  " ^ line ^ "\n")

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

(* EX2. Fold when both operands came back as LITERALS — which is the whole trick: the
   children have already been lowered, so this asks two strings it is holding rather
   than walking the tree a second time. One question per node, not one walk per node.

   The arithmetic is done in Int64, not OCaml's native `int`, which is 63 bits here:
   `3000000000 * 3000000000` fits in an i64 and does not fit in it, so folding in `int`
   would print a different answer from the same program written through a variable.
   Int64's div/rem truncate toward zero, which is what `sdiv`/`srem` do. *)
let fold_binop (operator : Ast.binop) (left : string) (right : string) :
    string option =
  match (Int64.of_string_opt left, Int64.of_string_opt right) with
  | Some a, Some b -> (
      match operator with
      | Ast.Add -> Some (Int64.to_string (Int64.add a b))
      | Ast.Sub -> Some (Int64.to_string (Int64.sub a b))
      | Ast.Mul -> Some (Int64.to_string (Int64.mul a b))
      (* division and remainder by zero must reach the machine: the program traps
         there, and folding would raise Division_by_zero inside the compiler *)
      | Ast.Div ->
          if b = 0L then None else Some (Int64.to_string (Int64.div a b))
      | Ast.Mod ->
          if b = 0L then None else Some (Int64.to_string (Int64.rem a b)))
  | _ -> None

(* Lower an expression: emit its instructions, return the operand holding its result —
   an immediate like "42", or a register like "%t3". *)
let rec emit_expr (context : context) (expression : Ast.expr) : string =
  match expression with
  | Ast.Int_lit (value, _) -> string_of_int value
  (* EX1: a name with no slot hands back the operand it was bound to. Note how this
     composes with EX2 for free: if that operand is a literal, the arithmetic above it
     folds, so `let a = 5; print(a * 2)` prints 10 without a constant propagator. *)
  | Ast.Var (name, _) when Hashtbl.mem context.values name ->
      Hashtbl.find context.values name
  | Ast.Var (name, _) ->
      let result_register = fresh context in
      emit context
        (Printf.sprintf "%s = load i64, ptr %s" result_register
           (slot_of context name));
      result_register
  | Ast.Unary (Ast.Neg, operand, _) -> (
      let operand_value = emit_expr context operand in
      match Int64.of_string_opt operand_value with
      | Some n -> Int64.to_string (Int64.neg n) (* EX2 *)
      | None ->
          let result_register = fresh context in
          emit context
            (Printf.sprintf "%s = sub i64 0, %s" result_register operand_value);
          result_register)
  | Ast.Binary (operator, left, right, _) -> (
      let left_operand = emit_expr context left in
      let right_operand = emit_expr context right in
      match fold_binop operator left_operand right_operand with
      | Some answer -> answer (* EX2 *)
      | None ->
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
            (Printf.sprintf "%s = %s i64 %s, %s" result_register opcode
               left_operand right_operand);
          result_register)
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
  (* EX1: nothing is ever assigned to this name, so it needs no memory at all — bind it
     to the operand its initializer produced and substitute that at every use. *)
  | Ast.Let { name; value; _ } when not (Hashtbl.mem context.reassigned name) ->
      Hashtbl.replace context.values name (emit_expr context value)
  | Ast.Let { name; value; _ } | Ast.Assign { name; value; _ } ->
      let slot = slot_of context name in
      let value_operand = emit_expr context value in
      emit context (Printf.sprintf "store i64 %s, ptr %s" value_operand slot)
  | Ast.Expr_stmt (expression, _) -> ignore (emit_expr context expression)

(* The whole module: the preamble, one `define i32 @main`, the statements in order.
   No target triple/datalayout on purpose — the driver passes -Wno-override-module and
   clang fills in the host triple. *)
let emit_llvm (program : Ast.program) : string =
  let context = create () in
  (* EX1's pre-pass: which names does the program ever assign to? It HAS to run before
     any lowering. `var v = 1; print(v); v = 2` gives v a slot from the first line, and
     the assignment that proves it is not reached until after the print is lowered. *)
  List.iter
    (function
      | Ast.Assign { name; _ } -> Hashtbl.replace context.reassigned name ()
      | Ast.Let _ | Ast.Expr_stmt _ -> ())
    program.Ast.stmts;
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
