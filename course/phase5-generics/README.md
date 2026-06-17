# Phase 5 — Generics & protocols (and Milestone M5)

The heart of Swift's type system: **protocol-oriented programming** — and its flagship
optimization. The phase builds abstraction in three steps and then, in the fourth, erases its
cost wherever the types are provable:

```
21: protocol P / conformance     →  WITNESS TABLES (+ methods, self, existentials, dispatch)
22: func g<T: P>                 →  the unspecialized model: T erased to its constraint
23: the container itself         →  fixed 3-word buffer + heap boxing; as? / as! by table identity
24: the optimizer strikes back   →  specialization + devirtualization  (M5)
```

The through-line: an existential is `{ payload, witness-table ptr }`; a generic is *the same
thing with static identity*; and static identity is fuel the optimizer burns — clone per
concrete type, fold proven dispatch, inline, and the protocol machinery vanishes from the hot
path.

| Concept | You implement | The payoff |
|---|---|---|
| `21-protocols-witness` | conformance check; existential wrap; static-vs-table dispatch; the tables | heterogeneous dispatch matching swiftc, incl. `-O` |
| `22-generics` | call-site type inference; the wrap/open call lowering | `pick(a, b).x` works — static identity, one erased copy |
| `23-existentials` | `as?`/`as!` lowering; the inline-or-box container | 5-word conformers, casts by value, `as!` aborts like swiftc (exit 134) |
| `24-specialization` | the devirtualization folds; the call-site specializer | **M5**: generic hot loops at **~104% of `swiftc -O`** (geomean, measured) |

Building this phase also caught and fixed (and pinned regressions for) **three real shipped
bugs** in earlier concepts: the Assign-wrap miscompile (optionals, 13–20), GVN's type-blind
value key (18–20), and the warnings-swallowing `--typecheck` driver.

**Milestone M5 (measured, `24-specialization/figs/m5_bench.png`):** specialization +
devirtualization + the second inline round turn protocol-oriented source into monomorphic code
within the band of `swiftc -O` — 101–108% across the suite — while unprovable call sites keep
honest dynamic dispatch, priced the same as the reference compiler's.
