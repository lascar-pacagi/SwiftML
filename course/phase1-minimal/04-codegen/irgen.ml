(* The IR generator: lower the checked AST straight to LLVM IR *text*.

   Phase-1 IRGen lowers to LLVM IR text (no SIL yet; that arrives in Phase 2). A simple
   stack/value model: every binding gets an `alloca`, reads are `load`, writes are
   `store`. Phase 4's mem2reg promotes these to SSA.

   >>> You build this in concept  phase1-minimal/04-codegen. <<<

   Design oracle: swift/lib/IRGen/* ; LLVM LangRef. We emit opaque-pointer IR (`ptr`),
   which Apple clang (LLVM 15+) consumes directly, and print via libc `printf`. *)

(* Lower the whole program to a string of LLVM IR. Build it in a [Buffer.t]:
     - a preamble: the `@.fmt` printf format constant + `declare i32 @printf(ptr, ...)`;
     - a fresh-name counter handing out `%t1`, `%t2`, … for instruction results;
     - a [slots : (string,string) Hashtbl.t] mapping each binding to its `alloca`
       register (`%name.addr`), emitted on first use;
     - [gen_expr : Ast.expr -> string] returns the operand (an i64 literal or a
       register): Int_lit -> the literal; Var -> a `load`; Unary Neg -> `sub i64 0, v`;
       Binary -> `add`/`sub`/`mul`/`sdiv`/`srem`; a print Call -> `call … @printf`;
     - [gen_stmt]: Let/Assign -> `gen_expr` then `store` into the slot; Expr_stmt ->
       just `gen_expr`;
     - wrap the body in `define i32 @main() { entry: <body> ret i32 0 }`.
   See the explainer (§3 "Build it") for the full walk-through. *)
let emit_llvm (prog : Ast.program) : string =
  ignore prog;
  failwith "TODO(04-codegen): implement IRGen.emit_llvm (AST -> LLVM IR text)"
