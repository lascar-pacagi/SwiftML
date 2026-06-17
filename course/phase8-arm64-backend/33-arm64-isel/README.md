# 33 · ARM64 instruction selection — Backend B begins

**Objective:** a **second backend, with no LLVM**. Lower our **SIL** directly to **ARM64 assembly**
(Apple/macOS arm64), assemble + link it with `clang` (driving `as`/`ld`), and run a real native
executable that matches `swiftc`. This is the first step of the from-scratch native track
(`SIL → isel → register allocation → machine code`) that runs alongside the LLVM spine.

v0 is a **naive stack machine**: every SIL value gets a stack-frame slot; each instruction loads
its operands into scratch registers (x9–x12), computes, and stores the result back. Correct but
memory-heavy — **concept 34's register-allocation ladder is what makes it fast** (and the reason
this baseline exists).

**You edit:** `isel.ml` — `TODO(33a)`: `sel_instr`, the per-SIL-op ARM64 templates (the "munch");
`TODO(33b)`: `sel_term`, the terminators (branches + return). The frame layout, prologue, constant
materialization, slot addressing, and the `arm64.ml` instruction IR + asm printer are given.

**Design oracle:** `../../../swift/lib/IRGen` is the LLVM path; the native track mirrors a classic
backend — read any ARM64 ABI reference (Apple's *Writing ARM64 Code for Apple Platforms*) for the
calling convention and the **variadic-on-the-stack** rule that `printf` needs.

## What this concept adds
- **`arm64.ml`** — the ARM64 instruction IR (`mov`/`add`/`mul`/`sdiv`/`cmp`/`cset`/`ldr`/`str`/
  `bl`/`b.cond`/…) + the `as`-assemblable asm printer (Apple syntax, `_`-prefixed symbols,
  `adrp`/`add @PAGE/@PAGEOFF` data addressing).
- **`isel.ml`** — SIL → ARM64: a per-function stack frame, a slot per SIL value, and one template
  per SIL op. Calls use the AAPCS64 arg registers x0–x7; `print` calls `_printf` with its variadic
  argument **on the stack** (the Apple arm64 ABI).
- **`--emit-asm`** (print the assembly) and **`build --native`** (Backend B: asm → `clang` → exe).

> **Scope (v0).** Int/Bool scalars, arithmetic, comparisons, `if`/`while`/`for`, function calls +
> recursion, `print`. Structs/enums/classes/ARC/arrays/closures are out of v0 (they need the
> runtime + aggregate lowering) and grow coverage in later concepts; an unsupported op lowers to a
> visible `; UNSUPPORTED` comment, never a silent miscompile. We lower the **raw `-Onone`**
> (memory-based) SIL — the optimized SSA (block-arg) form arrives with register allocation (34).

## Done when
`make lab C=phase8-arm64-backend/33-arm64-isel` green: a native ARM64 binary (fib, loops, division,
comparisons, print) **runs and matches `swiftc`**, the emitted asm has the expected shape (prologue,
`bl _printf`, `cmp`/`cset`, the cstring section), and **Backend B agrees with Backend A** (the LLVM
path) on the same program.
