# 32 · map / filter / reduce — closures meet collections

**Objective:** the higher-order trio — `map`, `filter`, `reduce` — over `Array<Int>`. This is the
**payoff of Phase 7**: concept-29 **closures** (a `%thickfn` you can call indirectly) finally meet
concept-31 **containers** (a heap buffer you can walk). Each of the three is a **counted loop over
the buffer** that calls the closure per element via `apply_value` — no new SIL, no new runtime.

**You edit:** `silgen.ml` — `TODO(32)`: lower `a.map(f)`, `a.filter(f)`, `a.reduce(init, f)`. A
`loop ~body_fill` helper (the counted walk) and an `rt_call` shortcut are given; you write the
three per-method bodies (build/return a result array for map/filter; fold into an accumulator slot
for reduce; branch on the predicate for filter).

**Design oracle:** `../../../swift/stdlib/public/core/Sequence.swift` (`map`/`filter`/`reduce` are
default `Sequence` methods — read their bodies: each is a `for`-loop calling the transform),
`SequenceAlgorithms.swift`.

## What this concept adds
- **`a.map { (x: E) -> R in … }`** → `[R]`: apply the closure to each element, collect the results.
- **`a.filter { (x: E) -> Bool in … }`** → `[E]`: keep the elements the predicate accepts.
- **`a.reduce(init) { (acc: R, x: E) -> R in … }`** → `R`: fold left from `init`.
- the typing rules that check each closure's shape against the array's element type.

> **Note on syntax.** We use the **parenthesised** closure-argument form —
> `a.map({ (x: Int) -> Int in x*2 })` and `a.reduce(0, { … })` — which both `swiftml` and `swiftc`
> accept. Swift's **trailing-closure** sugar (`a.map { … }`) and **`$0` shorthand** are a parser
> nicety, deferred to an exercise; the *lowering* (this concept's lesson) is identical either way.

> **Scope (v0).** `[Int]` arrays (concept 31's restriction); closures are explicitly typed
> (concept 29). `Dictionary` / `Set` / `Range`, the `Sequence`/`Collection` **protocols**, and
> `sorted`/`flatMap`/`zip` are the v1 — they need hashing + new container types (exercises). The
> trio is the unifying payoff; the rest is more of the same machine.

## Done when
`make lab C=phase7-closures-stdlib/32-stdlib-collections` green: `map`/`filter`/`reduce` (chained,
with captures, on empty arrays) match `swiftc` byte-for-byte at `-Onone` and `-O`; reduce returns a
scalar (no result array); a closure of the wrong shape is a clean diagnostic. **This closes
Milestone M7.**
