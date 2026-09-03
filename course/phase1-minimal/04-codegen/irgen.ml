(* The IR generator: lower the checked AST straight to LLVM IR *text*.

   Phase-1 IRGen lowers to LLVM IR text (no SIL yet; that arrives in Phase 2). A simple
   stack/value model: every binding gets an `alloca`, reads are `load`, writes are
   `store`. Phase 4's mem2reg promotes these to SSA.

   >>> You build this in concept  phase1-minimal/04-codegen. <<<

   Four holes, each one testable on its own — see explainer §3 for the order and
   `tests/test_irgen.ml` for the group each one turns green.

   Design oracle: swift/lib/IRGen/* ; LLVM LangRef. We emit opaque-pointer IR (`ptr`),
   which Apple clang (LLVM 15+) consumes directly, and print via libc `printf`. *)

(* GIVEN — the state the lowering shares, and its two helpers. swiftc bundles the same
   three things in `IRGenFunction` (IRGenFunction.h:77): somewhere to put instructions,
   a way to name values, and the map from source names to their storage. *)
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
   `alloca`; later uses must find the SAME register, so a reassigned `var` stores into
   its existing slot instead of allocating a second one.   Tests: `slots`. *)
let slot_of (c : ctx) (name : string) : string =
  ignore (c, name);
  failwith "TODO(04b): the name -> slot map (alloca on first use, remembered after)"

(* Lower an expression: emit its instructions, RETURN the operand holding its result —
   an immediate like "42", or a register like "%t3". That returned string is the whole
   interface: a literal emits nothing and returns itself, a binary emits one instruction
   and returns its register. §2 has the opcode table.

   `print` is the one call we lower, and it is Void in Swift: nothing consumes its result.
   Return an immediate for it — what printf hands back is an i32 (the character count),
   ill-typed anywhere an i64 is expected.   Tests: `arithmetic`, `literals`. *)
let rec emit_expr (c : ctx) (e : Ast.expr) : string =
  ignore (c, e, fresh, emit, slot_of, emit_expr);
  failwith "TODO(04a): lower an expression, returning its operand"

(* Lower a statement: `let`/`var` and assignment store into the name's slot; a bare
   expression is emitted for its instructions and its operand dropped.  Tests: `slots`. *)
let emit_stmt (c : ctx) (s : Ast.stmt) : unit =
  ignore (c, s, emit_expr);
  failwith "TODO(04c): lower a statement"

(* The whole module: the `@.fmt` constant and `declare i32 @printf(ptr, ...)`, then
   `define i32 @main() {`, `entry:`, every statement in order, `ret i32 0`, `}`.
   The preamble is module-level, so it is not written with `emit` (which indents for a
   function body) — build the string around `Buffer.contents c.buf`.  Tests: `module`. *)
let emit_llvm (prog : Ast.program) : string =
  ignore (prog, create, emit_stmt);
  failwith "TODO(04d): assemble the module"
