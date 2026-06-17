# 08 · SIL & SILGen

**Objective:** introduce **SIL** (our Swift Intermediate Language) and write **SILGen** — the pass
that lowers the type-checked AST into SIL. This is the pivot the whole phase has been building
toward: the AST is a *tree*, but a program's control flow is a *graph*, and SIL represents it
directly as **basic blocks** joined by branches. You'll see `if`/`while`/`for` become a control-flow
graph, and every variable become an `alloc_stack` slot touched by `load`/`store`.

**Prerequisites:** the Phase-2 front-end (05–07), which is **given and complete** here — your new
work is SILGen.

**You edit:** `silgen.ml` — the **control-flow lowering** (the `TODO(08)` holes in `gen_stmt`):
`if` → a `cond_br` diamond, `while`/`for` → a loop with a header and a back-edge, `break`/`continue`
→ branches to the loop's exit/header. The builder API (`emit`/`new_block`/`switch_to`/`terminate`),
the expression lowering (`gen_expr`), and the module driver (`lower_func`/`lower`) are given.

**Design oracle:** `../../../swift/lib/SILGen/` (`SILGenStmt.cpp` builds the CFG; `SILGenExpr.cpp`),
`../../../swift/lib/SIL/`, and `../../../swift/docs/SIL.rst`.

## What this concept adds

- **SIL** (`sil.ml`, a contract): basic blocks + terminators (`br`/`cond_br`/`return`), memory
  instructions (`alloc_stack`/`load`/`store`), arithmetic, `function_ref`/`apply`, `print`.
- **SILGen** (`silgen.ml`): AST → SIL. Raw, **memory-based** SIL (no SSA — Phase-4's mem2reg promotes
  it; that's where you'll learn SSA).
- `swiftml2 --emit-sil` (recognizable, simplified swiftc-SIL syntax) + a SIL **verifier**.

We still don't *run* programs — that's concept 09 (IRGen: SIL → LLVM). 08 stops at emitting verified
SIL, tested FileCheck-style against the SIL shape.

## Done when

`make lab C=phase2-types-flow/08-sil-silgen` is green: the cram FileCheck test matches the SIL shape
(`cond_br`, the loop back-edge, the `if` diamond), the alcotest structural checks pass, and the
verifier accepts the SILGen output.
