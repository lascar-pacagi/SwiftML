(* The IR generator: lower the checked AST straight to LLVM IR *text*.

   Phase-1 IRGen lowers to LLVM IR text (no SIL yet; that arrives in Phase 2). A simple
   stack/value model: every binding gets an `alloca`, reads are `load`, writes are
   `store`. Phase 4's mem2reg promotes these to SSA.

   >>> You build this in concept  phase1-minimal/04-codegen. <<<

   Design oracle: swift/lib/IRGen/* ; LLVM LangRef. We emit opaque-pointer IR (`ptr`),
   which Apple clang (LLVM 15+) consumes directly, and print via libc `printf`. *)

(* Lower the whole program to a string of LLVM IR: a preamble, one `define i32 @main`,
   and the statements in order. The model is MEMORY-BASED — every binding gets an
   `alloca`, reads are `load`, writes are `store` — which is what Phase 4's mem2reg
   later promotes to SSA. Every instruction result needs a fresh name.
   The IR for each construct is in explainer §3. *)
let emit_llvm (prog : Ast.program) : string =
  (* GIVEN — the output buffer and the two helpers every case below uses.
     [emit] appends one instruction, indented like the body of a function.
     [fresh] hands out register names nobody has used yet (%t1, %t2, …); asking for a new
     one per result is how the SSA "written exactly once" rule is kept in practice.
     ("%%" in the format string is a literal '%'.) *)
  let buf = Buffer.create 256 in
  let emit (line : string) : unit = Buffer.add_string buf ("  " ^ line ^ "\n") in
  let next_reg = ref 0 in
  let fresh () : string =
    incr next_reg;
    Printf.sprintf "%%t%d" !next_reg
  in
  ignore (prog, buf, emit, fresh);
  failwith "TODO(04-codegen): implement IRGen.emit_llvm (AST -> LLVM IR text)"
