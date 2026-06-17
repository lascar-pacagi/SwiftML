# Phase 6 — Reference types & ARC (and Milestone M6)

Swift's other world: `class` — and the machinery that makes shared, heap-allocated objects
safe and fast. Four concepts, one arc: build references, manage their lifetimes, make the
rules checkable, then make them cheap.

```
25: class / inheritance / override   →  heap objects + VTABLES (header reserves the refcount)
26: the ARC runtime                  →  retain/release insertion; deinit TIMING = the oracle
27: ownership SSA                    →  copy/destroy_value, load [take], THE VERIFIER
28: the ARC optimizer                →  copy propagation + WMO devirt  (M6)
```

| Concept | You implement | The payoff |
|---|---|---|
| `25-classes-vtables` | the vtable build (inherit/override-in-place/append); dispatch; its emission | reference semantics + overrides matching swiftc, incl. self-calls through superclass methods |
| `26-arc-runtime` | the ownership-transfer rule; the field-destroy chain; `rt.release` | **12/12 deinit orderings byte-identical to swiftc** at `-Onone` and `-O` — including the two-chain deallocation order a probe caught us getting wrong |
| `27-ownership` | the ownership verifier | ARC bugs become compile errors; the verifier's first run caught our own param-spill flaw and made the compiler smaller |
| `28-arc-optimization` | the copy-propagation rewrite | **M6**: 30M retain/release pairs deleted; **126% of `swiftc -O`** (geomean, measured) with every deinit ordering intact |

The phase's through-line is the *discipline ladder*: probes pin behavior (26), structure makes
the rules statable (27), and only then does optimization become a set of small, provable
rewrites (28) — the same ladder swiftc climbed when it moved SIL to OSSA.

**Milestone M6 (measured, `28-arc-optimization/figs/m6_bench.png`):** identical deinit
behavior to swiftc across the full lifetime suite, and the ARC optimizer erases the naive
traffic — borrow-copy loops at 143%/110% of `swiftc -O`, with the load-sourced
must-keep case proving the eliminations stop exactly where observability begins.
