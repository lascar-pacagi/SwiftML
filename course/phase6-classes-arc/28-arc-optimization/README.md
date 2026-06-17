# 28 · ARC optimization — Milestone M6

**Objective:** spend concept 27's structure. The ownership-SSA form makes one fact checkable:
*this `copy_value`'s +1 is consumed by exactly that `destroy_value`*. When the copy's whole
lifetime sits inside its source's lifetime, the pair is pure overhead — the count never
touches zero inside the bracket, no deinit observation can move — so the optimizer deletes
it. This is **copy propagation**, the flagship ARC rewrite (swiftc: OSSA `CopyPropagation`),
plus **whole-module class devirtualization** (a subclass-free class has exactly one possible
vtable — dispatch directly, then inline). Together they close Phase 6: **Milestone M6**.

**Prerequisites:** concepts 26–27 (the runtime, the ownership structure, the verifier).

**You edit:** `opt.ml` — `TODO(28)`: the copy-propagation rewrite — the three eligibility
checks (single destroy-consumer in-block with all uses inside the bracket; source outlives it:
a parameter, or an owned value consumed later in the same block) and the deletion/redirect.
The use-collection scaffolding, the fixpoint loop, and the WMO devirt arm are given.

**Design oracle:** `../../../swift/docs/ARCOptimization.md` (read it cover to cover — our
pass is its §"copy propagation" in miniature),
`swift/lib/SILOptimizer/Transforms/CopyPropagation.cpp`,
`swift/lib/SILOptimizer/Transforms/SpeculativeDevirtualizer.cpp`.

## Results (M6 — measured, see `figs/m6_bench.png`)

| bench | swiftml -Onone | swiftml -O | swiftc -O | % of swiftc -O |
|---|---|---|---|---|
| borrowloop (copy/destroy ×30M) | 0.062s | **0.009s** | 0.012s | 143% |
| handoff (3 chained copies ×20M) | 0.105s | **0.053s** | 0.059s | 110% |

**Geomean 126% of `swiftc -O`** (M4's overflow caveat stands); 30 million retain/release pairs
deleted from `borrowloop` — 6.9× over our own `-Onone`. And the correctness half of M6 holds
through it all: **12/12 deinit-order parity at `-O`**, including the two adversarial probes —
a deinit-bearing copy (timing unchanged) and the **load-sourced copy that must NOT be removed**
(the slot is overwritten inside the bracket; keeping the old object alive was the copy's whole
job).

## What this concept adds

- **`copy_propagation`** in the `-O` pipeline (after mem2reg; again post-inline) — one rewrite
  per sweep to a fixpoint (deletions shift indices; a stale-index cascade corrupted chained
  copies until the one-per-sweep rule — kept as a lesson).
- **WMO class devirtualization** in `devirt_module`: no subclasses anywhere in the module ⇒
  the dynamic type is the static type ⇒ direct call ⇒ the inliner eats it. Overridden
  hierarchies keep their vtable dispatch (probed).
- A composition insight, pinned by a test: the pass alone must keep a *return-consumed* copy
  (it transfers ownership) — but after inlining exposes both ends in one function, the full
  pipeline may legitimately erase it. Passes are sound alone *and* compose.

> **Scope (v0).** Same-block brackets only (cross-block needs liveness — exercise); no
> retain/release *motion* (sinking out of loops — exercise); no dead-object elimination
> (alloc+init+destroy of a never-escaping deinit-free object — exercise).

## Done when

`make lab C=phase6-classes-arc/28-arc-optimization` is green (copies vanish where provable,
survive where not, deinit timing untouched at `-O`) and
`make bench C=phase6-classes-arc/28-arc-optimization` shows `-O` beating `-Onone` with
`swiftc -O` in the band. **That's Milestone M6 — and Phase 6 complete.**
