# 41 — the constraint solver

**Objective.** Replace the bidirectional checker you wrote in concepts 05–07 with the design
swiftc actually uses: generate constraints, solve them by search, write the answer back.

**Why it needs its own concept.** A bidirectional checker decides every node the moment it
reaches it, which works because its rules are local. Overloading is not local. Swift lets two
functions share a name — including when they differ only in what they RETURN — so

```swift
func g() -> Int    { return 1 }
func g() -> Double { return 2.5 }
let c: Double = g()
let d: Int    = g()
```

is two different functions called from two identical call sites. Nothing about `g()` decides
which; only the type the context wants back does. `infer` has nothing to look at, and there is
no order in which a local rule could reach the answer. That is the wall this concept is on the
other side of.

**Prereqs.** 05 (bidirectional checking, literal defaulting), 07 (functions, two-pass
collection of signatures).

**A leaf.** This concept forks concept 07's front end rather than extending concept 40's, so
the solver is the only thing that is new, and nothing downstream depends on it. Concept 14 did
the same.

## What you build

| file | mirrors | yours? |
|---|---|---|
| `constraints.ml` | `include/swift/Sema/Constraint.h` | given |
| `csgen.ml` | `lib/Sema/CSGen.cpp` | given |
| `cssolver.ml` | `lib/Sema/CSSolver.cpp`, `CSStep.cpp` | **`TODO(41a-c)`, and `41e`** |
| `csapply.ml` | `lib/Sema/CSApply.cpp` | **`TODO(41d)`** |

- `TODO(41a)` `unify` — make two types equal, with a trail so a guess can be undone
- `TODO(41b)` `simplify` — solve everything that needs no guess; keep what does
- `TODO(41c)` `solve` — the depth-first search over disjunctions, scored, with a budget
- `TODO(41d)` `csapply` — rebuild the tree with the types and the chosen declarations on it
- `TODO(41e)` the **splitter** — an optional second rung. `[ cs ]` is correct and every test
  passes with it; §5 measures what it costs.

## Definition of done

1. `make lab C=phase9-inference/41-constraint-solver` green, including `tests/oracle.t` —
   every program in the corpus gets the same verdict from your solver and from
   `swiftc -typecheck`.
2. `--emit-constraints` shows the system; `--emit-tast` shows which declaration each call
   resolved to (`g#0` / `g#1`).
3. The explainer renders and its figure comes from a real run.
