# course/ — build the Swift compiler in OCaml

Build **`swiftml`**, a real Swift compiler, from scratch, one working slice at a time — with the
same architecture as Apple's (`Parse → Sema → SILGen → SIL → optimizer → IRGen → LLVM → native`,
plus a from-scratch ARM64 backend). Validated against the real `swiftc` at every step.

**New here?** Read [`GUIDE.md`](GUIDE.md). **Full curriculum:** [`../PLAN.md`](../PLAN.md).
**Conventions:** [`../CLAUDE.md`](../CLAUDE.md).

```bash
make setup                                # one-time: OCaml + dune + deps (Phase 0)
make setup-hooks                          # ONLY if you will share this clone or send fixes
                                          #   upstream — then: make claim-all
make build                                # compile the compiler

# working through a concept
make claim C=phase1-minimal/01-lexer      # "these stage files are mine" — before you start
make explainer C=phase1-minimal/01-lexer  # render the lesson (Quarto)
make lab C=phase1-minimal/01-lexer        # that concept's tests  (RED until you fill it in)
make exercises C=phase1-minimal/01-lexer  # just the §6 exercises (they also run in `make lab`)
make oracle F=tests/programs/arith.swift  # differential vs swiftc

# where a concept has bench/ (01-lexer, 20-llvm-opt)
make bench C=phase1-minimal/01-lexer      # how fast?
make profile C=phase1-minimal/01-lexer    # slow WHERE? (cost per construct, allocation sites)
make profile-cpu C=phase1-minimal/01-lexer [RUNG=v1]   # sampled call tree: your code vs the GC

# before sharing the repo
make save                                 # snapshot your claimed files (gitignored work/)
make check-pristine                       # does HEAD ship a skeleton that is already solved?
```

`make test` runs the whole tree and is **RED by design** on a fresh clone: every concept ships
skeletons whose tests fail until you write the code. `make lab C=…` is the per-concept version,
and the one you actually watch. [`GUIDE.md §7b`](GUIDE.md) explains `claim` and the pre-commit
guard — the short version is that you edit skeletons in place, so your work must never be
committed, and one `make claim` per concept makes that automatic.

Layout: each `phaseN-*/` is a complete compiler for a growing subset; inside it, each
`NN-concept/` is **one stage** — the source you edit (`lexer.ml`, `parser.ml`, …) lives right
there, next to its tests and `solution/`. The stages are dune libraries that chain
(lexer ← parser ← sema ← codegen), and the phase's `bin/` assembles them into the **`swiftml`**
binary. `tooling/` has the oracle/FileCheck/bench harnesses; `tests/programs/` is the shared
`.swift` corpus; `../swift/` is the read-only design oracle.
