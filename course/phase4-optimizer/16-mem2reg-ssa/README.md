# 16 · mem2reg & SSA

**Objective:** promote the raw, memory-based SIL — all those `alloc_stack`/`load`/`store` from
concept 08 — to **SSA form**, where each value is assigned once and a loop-carried value is a
**basic-block argument** (swiftc's "phi"). This is **mem2reg**, the from-zero **SSA construction**
lesson: **dominator trees → dominance frontiers → liveness → block-argument placement → renaming**.
It's the deliberate payoff of choosing memory-based SIL back in Phase 2 — and what makes every other
optimization powerful, because they can finally see *through* memory.

**Prerequisites:** the pass manager (concept 15). SIL now carries **block arguments** (a new field on
blocks; `Br`/`Cond_br` pass argument lists), and IRGen lowers them to LLVM `phi`. Those changes are
given.

**You edit:** `opt.ml` — `TODO(16)`: the **renaming** walk inside `mem2reg`, the heart of SSA
construction. (The analyses — dominators, dominance frontiers, liveness — and the phi placement are
given; you thread each slot's *reaching value* down the dominator tree, replacing loads, removing
stores, and filling in the block arguments.)

**Design oracle:** `../../../swift/lib/SILOptimizer/Mandatory/SILMem2Reg.cpp` (swiftc's mem2reg) and
the classic Cytron et al. SSA-construction algorithm.

## What this concept adds

- SIL **basic-block arguments** (the SSA join form) + IRGen → LLVM `phi`.
- The **mem2reg** pass: find promotable slots (an `alloc_stack` used only as a `load`/`store`
  address), place block arguments at the **iterated dominance frontier** of each slot's stores
  (pruned by **liveness**), and **rename** so loads become the reaching SSA value and stores vanish.
- mem2reg runs first in the `-O` pipeline, so constant folding / DCE then see real values, not loads.

> **Scope (v0).** Promotes scalar/aggregate slots accessed only by whole `load`/`store`. Struct slots
> accessed by `struct_element_addr` are **not** promoted (left valid) — SROA (splitting aggregates) is
> Exercise 2. Trivial phis aren't pruned (harmless; Exercise 4).

## Done when

`make lab C=phase4-optimizer/16-mem2reg-ssa` is green: `--emit-sil` is memory-heavy, `--sil-opt` shows
the slots gone and the loop carrying its values as **block arguments** (`bb1(%i, %s):`), and **`-O`
preserves behavior** — loops, recursion, structs, enums, and optionals all still match `swiftc`.
