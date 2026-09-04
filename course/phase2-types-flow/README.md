# Phase 2 — Types, control flow, functions (and the introduction of SIL)

Phase 1 was an `Int`-only calculator. Phase 2 turns `swiftml` into a *real* language with a *real*
type system, and rebuilds the pipeline into the exact shape Apple's compiler uses:

```
Phase 1:  Parse → Sema → IRGen → LLVM
Phase 2:  Parse → Sema → SILGen → SIL → (mandatory passes) → IRGen → LLVM
                          └──────── the new middle, introduced at concept 08 ────────┘
```

**The growing subset:** `Bool` / `Double` / `String` alongside `Int`; type annotations
(`let x: Double = 1`); operator typing and literal coercion; `if`/`else`, `while`, `for i in a..<b`,
`break`/`continue`, short-circuit `&&`/`||`; `func` with parameters, returns, recursion. By the end
the pipeline runs through **SIL** (memory-based at this stage — SSA arrives with mem2reg in
Phase 4, concept 16) and `--emit-sil` reads like
swiftc's.

## How Phase 2 relates to Phase 1

Each phase is a **complete, self-contained compiler** for its subset (the metalgrad style). Phase 2
carries the Phase-1 design forward as its own evolved stage libraries (distinct dune names), so you
can read and run Phase 2 without flipping back. **You already built the lexer and parser in Phase 1**,
so Phase 2 *gives* you the evolved front-end — typed literals (`true`, `3.14`, `"hi"`), `:` type
annotations, comparison/logical operators — as written contracts. Your hands-on work each concept is
the **new semantic machinery**, the part that's genuinely new at this phase.

Later-phase skeletons **carry your earlier work forward already working** — you only fill `TODO`
holes for the *new* functionality of each phase (you never re-type the Phase-1 lexer/parser).

| Concept | You implement | Checked against |
|---|---|---|
| `05-types-inference` | new front-end holes (`"…"`/`3.14` literals, `: T` annotations, `== < …` ops) **+** `sema.ml` — **bidirectional type checking** (`Int`/`Bool`/`Double`/`String`, inference, operator typing, coercions) | rejects ill-typed programs like `swiftc`; parity |
| `06-control-flow` | `if`/`while`/`for`, `break`/`continue`, short-circuit `&&`/`\|\|` | parity on the control-flow corpus |
| `07-functions` | `func`, calls, recursion, the call ABI | parity; `fib` matches |
| `08-sil-silgen` | **SILGen** — lower the checked AST to **SIL** (memory-based raw IR); `--emit-sil` | SIL shape mirrors swiftc's `-emit-sil` |
| `09-sil-to-llvm` | **IRGen from SIL** — the instruction and terminator lowering | programs build and RUN, byte-identical to swiftc on the phase corpus |

**Milestone M2:** functions and control flow compile *through SIL* and run; `--emit-sil` is readable
and mirrors swiftc's structure; the output and exit code of every corpus program match `swiftc`
(`Int`/`Bool`/control flow/functions — `Double` printing and `String` are the documented gaps).
Definite initialization is swiftc's other mandatory SIL pass, and it is **vacuous here**, because
every `let`/`var` in this subset is initialized where it is declared; writing the dataflow pass for
an uninitialized `var x: Int` is concept 09's first exercise.

**Design oracle for the phase:** `../../../swift/lib/Sema/` (type checking, the constraint system),
`../../../swift/lib/SILGen/`, `../../../swift/lib/SIL/`, and `docs/SIL/SIL.md` in the swift tree.
