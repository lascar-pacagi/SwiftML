# course/ — build the Swift compiler in OCaml

Build **`swiftml`**, a real Swift compiler, from scratch, one working slice at a time — with the
same architecture as Apple's (`Parse → Sema → SILGen → SIL → optimizer → IRGen → LLVM → native`,
plus a from-scratch ARM64 backend). Validated against the real `swiftc` at every step.

**New here?** Read [`GUIDE.md`](GUIDE.md). **Full curriculum:** [`../PLAN.md`](../PLAN.md).
**Conventions:** [`../CLAUDE.md`](../CLAUDE.md).

```bash
make setup                                # one-time: OCaml + dune + deps (Phase 0)
make build                                # compile the compiler

# working through a concept
make explainer C=phase1-minimal/01-lexer  # render the lesson (Quarto)
make lab C=phase1-minimal/01-lexer        # that concept's tests  (RED until you fill it in)
make exercises C=phase1-minimal/01-lexer  # just the §6 exercises (they also run in `make lab`)
make oracle F=tests/programs/arith.swift  # differential vs swiftc (needs a back end: 04+)

# where a concept has bench/ (01-lexer, 20-llvm-opt)
make bench C=phase1-minimal/01-lexer      # how fast?
make profile C=phase1-minimal/01-lexer    # slow WHERE? (cost per construct, allocation sites)
make profile-cpu C=phase1-minimal/01-lexer [RUNG=v1]   # sampled call tree: your code vs the GC
```

`make test` runs the whole tree and is **RED by design** on a fresh clone: every concept ships
skeletons whose tests fail until you write the code. `make lab C=…` is the per-concept version,
and the one you actually watch.

### Will anyone clone from *you*?

If not — you cloned this to learn from it — skip this section. You edit the skeletons in place and
your copy is yours; commit it or don't.

If yes (you maintain the course, or you want to send a correction upstream without your answers in
the diff), two one-time commands keep your work out of what you publish:

```bash
make setup-hooks     # install the pre-commit guard (local to this clone)
make claim-all       # mark every concept's stage files as yours — the hook now refuses
                     #   to commit them   (or: make claim C=<one concept> at a time)
```

Corrections to the *given* parts of a claimed file still go through: stage those hunks with
`git add -p` and commit with `SKELETON_FIX="<the path>"` (naming the file, not a blanket bypass). Two more helpers:

```bash
make save                                 # snapshot your claimed files into gitignored work/
make restore C=phase1-minimal/01-lexer    # put the shipped skeleton back
make check-pristine                       # does HEAD ship a skeleton that is already solved?
make check-shipped C=<concept>            # ...and is that concept actually RED on HEAD?
```

[`GUIDE.md §7b`](GUIDE.md) has the full story.

Layout: each `phaseN-*/` is a complete compiler for a growing subset; inside it, each
`NN-concept/` is **one stage** — the source you edit (`lexer.ml`, `parser.ml`, …) lives right
there, next to its tests and `solution/`. The stages are dune libraries that chain
(lexer ← parser ← sema ← codegen), and the phase's `bin/` assembles them into the **`swiftml`**
binary. `tooling/` has the oracle/FileCheck/bench harnesses; `tests/programs/` is the shared
`.swift` corpus; `../swift/` is the read-only design oracle.
