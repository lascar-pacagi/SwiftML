# 19 · Function inlining

**Objective:** replace a call with the **callee's body**. Inlining makes small functions *free* — but
its bigger payoff is that it exposes the call's arguments and results to the *other* passes, so
folding, CSE, and DCE suddenly work across what used to be a call boundary.

**Prerequisites:** the optimizer through concept 18. Inlining is the first **inter-procedural** pass —
it needs the whole module (the caller *and* the callee), so it runs as a module-level transform before
the per-function pipeline.

**You edit:** `opt.ml` — `TODO(19)`: the inline transform — renumber the callee's values, bind its
parameters to the actual arguments, splice its instructions in place of the call, and make the call
result become the callee's return value.

**Design oracle:** `../../../swift/lib/SILOptimizer/Transforms/` (the SIL inliner + its cost model);
LLVM's `Inliner`.

## What this concept adds

- **`inline_module`**: for each call whose callee is a **single-block leaf** (one block, no `apply`
  inside, not `main`), splice the callee's body at the call site (values renumbered, params → args),
  replace the call result with the callee's return value, then drop callees that are no longer called.
- Run **first** in `-O`, so mem2reg/fold/CFG/GVN/DCE then operate across the old boundary: `sq(5)`
  becomes `5*5` becomes `25`.

> **Scope (v0).** Single-block leaf callees only — guarantees termination (a leaf can't recurse) and
> needs no block surgery. **Multi-block callees** (internal control flow) and a **cost model** (which
> calls are worth inlining) are v1 / exercises. Recursive functions are correctly *not* inlined.

## Done when

`make lab C=phase4-optimizer/19-inlining` is green: `sq(5)` is inlined, folded to `25`, and `@sq` is
removed; nested calls and inlining inside loops work; recursive `fib` is left alone; and **`-O` still
matches `swiftc`**.
