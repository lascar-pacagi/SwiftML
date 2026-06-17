# 09 · SIL → LLVM (IRGen) — programs run

**Objective:** write **IRGen** — lower the SIL module to **LLVM IR** — and wire up `build`, so
Phase-2 programs **compile to a native executable and run**, matching `swiftc` byte-for-byte. This is
the end of Phase 2 and **Milestone M2**: `if`/`while`/`for`, functions, and recursion all execute.

**Prerequisites:** the front-end + SIL + SILGen (05–08), all given and complete. Your new work is
IRGen.

**You edit:** `irgen.ml` — the two `TODO(09)` holes in `gen_instr` and `gen_term`: lower each SIL
instruction and terminator to an LLVM line. The mapping is nearly one-to-one (SIL is already
memory-based with basic blocks), so the plumbing (`llty`, the buffers, the `gen_func` shell, the
`gen_binop` opcode table, `gen_print`) is given.

**Design oracle:** `../../../swift/lib/IRGen/` (`IRGenSIL.cpp` walks SIL and emits LLVM), the LLVM
Language Reference (`https://llvm.org/docs/LangRef.html`).

## What this concept adds

- **IRGen** (`irgen.ml`): SIL → LLVM IR text. SIL value → LLVM operand; `alloc_stack` → `alloca`,
  `load`/`store` → LLVM `load`/`store`, typed `binop` → `add i64`/`fadd double`/`icmp slt i64`/…,
  `cond_br`/`br`/`return` → LLVM `br`/`ret`, `apply` → `call`, `print` → a `printf` call.
- `swiftml2 --emit-llvm` and `swiftml2 build <file> [-o <out>]` (LLVM IR → `clang` → native).
- **Runtime parity** with `swiftc` on the Int/Bool/control-flow/function corpus.

> **Scope notes (documented simplifications).** The runtime corpus is `Int`/`Bool`/control-flow/
> functions. `Double` *printing* and `String` runtime (concatenation, comparison) aren't matched to
> swiftc here (Swift's exact `Double` formatting and string memory management are later work), and the
> mandatory **definite-initialization** diagnostic is vacuous in our subset (every `let`/`var` is
> initialized at its declaration) — adding uninitialized `var x: T` + a DI dataflow pass is Exercise 1.

## Done when

`make lab C=phase2-types-flow/09-sil-to-llvm` is green: the cram test **builds and runs** programs and
checks their output (and FileChecks the IR), and the alcotest pins the emitted-IR shape. A program
compiled with `swiftml2 build` produces the same output as one compiled with `swiftc`.
