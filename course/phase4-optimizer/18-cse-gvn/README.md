# 18 · CSE / GVN (global value numbering)

**Objective:** stop computing the same thing twice. **Common-subexpression elimination** via **global
value numbering** recognizes that two instructions compute the *same value* and keeps only one,
redirecting the other's uses to it — correctly across blocks, using **dominance**.

**Prerequisites:** the optimizer through concept 17. mem2reg gives SSA (so each value has one
definition, which is what makes "are these the same?" a structural question).

**You edit:** `opt.ml` — `TODO(18)`: `value_key` (a stable key identifying *what a pure instruction
computes* — equal keys mean equal values) and the **dominance-scoped numbering** walk (a dominator-tree
DFS with a `key → value` table that's valid only within the current dominance scope).

**Design oracle:** `../../../swift/lib/SILOptimizer/` (CSE/RedundantLoadElimination); LLVM's
`EarlyCSE`/`GVN`.

## What this concept adds

- **`gvn`**: build a dominator tree, walk it, and number each **pure** instruction by `(op, operand
  value-numbers)`. If an equal computation already exists *in the current dominance scope*, the
  instruction is redundant — redirect its uses and drop it. Impure/unique instructions (`load`,
  `store`, `apply`, `print`, `alloc_stack`, `struct_element_addr`) are never CSE'd.
- Added to the `-O` pipeline after folding (so equal expressions are exposed) and before DCE/cleanup.

> **Scope (v0→v1).** This is the global, dominance-scoped version (a value computed in a block can be
> reused in any block it dominates — including across an `if`'s join). Local (per-block) CSE is the
> simpler v0. **Redundant-load elimination** (CSE'ing `load`s) needs alias analysis — Exercise 2.

## Done when

`make lab C=phase4-optimizer/18-cse-gvn` is green: `x * x + x * x` drops from two multiplies to one in
`--sil-opt`, a subexpression repeated in a condition and its branches is computed once, function calls
are **not** merged, and **`-O` still matches `swiftc`**.
