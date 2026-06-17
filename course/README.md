# course/ — build the Swift compiler in OCaml

Build **`swiftml`**, a real Swift compiler, from scratch, one working slice at a time — with the
same architecture as Apple's (`Parse → Sema → SILGen → SIL → optimizer → IRGen → LLVM → native`,
plus a from-scratch ARM64 backend). Validated against the real `swiftc` at every step.

**New here?** Read [`GUIDE.md`](GUIDE.md). **Full curriculum:** [`../PLAN.md`](../PLAN.md).
**Conventions:** [`../CLAUDE.md`](../CLAUDE.md).

```bash
make setup     # one-time: OCaml + dune + deps (Phase 0)
make build     # compile the compiler
make test      # fast test subset
make lab C=phase1-minimal/01-lexer        # one concept's tests
make oracle F=tests/programs/arith.swift  # differential vs swiftc
make explainer C=phase1-minimal/01-lexer  # render the lesson (Quarto)
```

Layout: each `phaseN-*/` is a complete compiler for a growing subset; inside it, each
`NN-concept/` is **one stage** — the source you edit (`lexer.ml`, `parser.ml`, …) lives right
there, next to its tests and `solution/`. The stages are dune libraries that chain
(lexer ← parser ← sema ← codegen), and the phase's `bin/` assembles them into the **`swiftml`**
binary. `tooling/` has the oracle/FileCheck/bench harnesses; `tests/programs/` is the shared
`.swift` corpus; `../swift/` is the read-only design oracle.
