# 24 · Specialization & devirtualization — Milestone M5

**Objective:** burn the static fuel. Concepts 21–23 built abstraction with a runtime cost: wrap,
table-dispatch, open, and an inliner wall. This concept builds the two optimizer passes that
erase it wherever the types are provable:

- **Devirtualization** — when an existential's concrete type is *proven* (its SSA def is the
  `init_existential`, or the value is already concrete inside a clone), fold: witness dispatch →
  **direct call**; open → **the payload itself**; identity test → **a constant**.
- **Generic specialization** — clone `g<T: P>` per proven concrete type: `g$A` takes a raw `A`,
  its dispatches devirtualize, the inliner eats the direct calls, and the Phase-4 pipeline
  finishes the job. Unprovable sites stay on the erased original — both worlds coexist, exactly
  like swiftc.

**Prerequisites:** the full Phase-5 protocol/generic machinery (21–23) and the Phase-4 optimizer.

**You edit:** `opt.ml` — `TODO(24a)` the devirtualization folds; `TODO(24b)` the call-site
specializer (proof collection, clone trigger, arg unwrapping, result retyping). The clone
machinery (`clone_specialized`, `retypable`) and the worklist are given.

**Design oracle:** `../../../swift/lib/SILOptimizer/Transforms/SpeculativeDevirtualizer.cpp`,
`swift/lib/SILOptimizer/Utils/Generics.cpp` (the generic specializer),
`swift/docs/OptimizationTips.rst` ("whole-module optimization" is largely about making types
provable).

## The pipeline (the cascade is the concept)

```
inline → mem2reg/SSA → SPECIALIZE → DEVIRTUALIZE → inline again → fold/CFG/GVN/DCE → LLVM -O2
```

Specialization creates direct-call work; the second inline round is where the abstraction
actually dies: `dbl<T>` over `A` ends as one `struct_extract` and an `add` — GVN even merges the
two `t.v()` calls.

## Results (M5 — measured, see `figs/m5_bench.png`)

| bench | swiftml -Onone | swiftml -O | swiftc -O | % of swiftc -O |
|---|---|---|---|---|
| genloop (generic, 30M iters) | 0.159s | **0.089s** | 0.090s | 101% |
| exloop (existentials, 10M) | 0.064s | **0.030s** | 0.032s | 104% |
| maxgen (`biggest<T>`, 8M) | 0.050s | **0.011s** | 0.012s | 108% |

**Geomean 104% of `swiftc -O`** — monomorphic-grade code from protocol-oriented source (same
overflow-semantics caveat as M4). `make bench C=phase5-generics/24-specialization` re-measures.

> **Scope (v0).** Specializes single-type-parameter generics whose `T` is provable at the call
> site (the wrap is local SSA, or we're already inside a clone — recursion specializes
> naturally). Bails honestly on: functions that build their own existentials of the same
> constraint (retyping would be unsound), ambiguous multi-conformance dispatch, and unprovable
> arguments. Speculative devirtualization (guess + guard) is an exercise.

## Done when

`make lab C=phase5-generics/24-specialization` is green. One cram file per hole —
`opt-devirt.t` (the three folds, and the cases that must NOT fold) and `opt-specialize.t` (the
clones, the cascade, and the calls that must stay erased) — plus the given `sema-subset.t` and
the headline `oracle.t`, which asks swiftc on every run: 21 programs where `swiftc -typecheck`
and `--typecheck` must agree on accept-or-reject, and 18 built four ways (`swiftc -Onone`,
`swiftc -O`, `./lab.exe build`, `./lab.exe build -O`) whose stdout and exit code must be
identical — half of them deliberately unprovable, so a fold that fires without its proof shows
up as a wrong answer. Then `make bench C=…` for the M5 gate. **That's Milestone M5 — and Phase 5
complete.**
