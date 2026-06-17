# swiftml — a Swift compiler from scratch, in OCaml

**swiftml** is a working compiler for a growing subset of Swift, built **from scratch in OCaml**,
one concept at a time, with the **same architecture as Apple's real compiler**. It is a course as
much as a compiler: 41 self-contained concepts (`00`–`40`) grouped into 9 phases, where each *phase*
is a **complete compiler** for a bigger slice of the language than the one before.

It is also honest about itself. Every concept is checked against the real `swiftc`: compile the same
`.swift` with swiftml and with Apple's toolchain and assert **identical stdout and exit code**, at
`-Onone` and `-O`. The performance phases are *measured* against `swiftc -O`.

> Status: **phases 0–8 complete, milestones M0–M8 met.** A 31-program classical suite matches
> `swiftc` byte-for-byte at both optimization levels. See [`course/PROOFREAD.md`](course/PROOFREAD.md)
> for a critical review and the open follow-ups.

## The idea

- **Two oracles keep it honest.** `swift/` is Apple's real compiler *source* — the **design
  oracle** we mirror (`lib/Parse`, `lib/SILGen`, `lib/SIL`, …). `/usr/bin/swiftc` is the installed
  toolchain — the **behavioral oracle** we diff against, and the **perf baseline** we chase.
- **Two backends from one front end.** Everything is lexed, parsed, type-checked, and lowered to
  **SIL** (Swift Intermediate Language). From there it goes down the **LLVM spine** (faithful to
  swiftc) *or* through a **from-scratch ARM64 backend** built by hand in Phase 8.
- **Learn by doing.** Each concept ships a deep tutorial and a code skeleton with `TODO` holes; you
  fill in the new logic, and a test suite is **RED on the skeleton, GREEN once the answer is in
  place**.

![The swiftml pipeline: one front end, two backends.](course/course-map/figs/pipeline.png)

A full pedagogical walkthrough of the whole pipeline and where every concept fits is in
[`course/course-map/`](course/course-map/explainer.qmd) (rendered:
`course/course-map/explainer.pdf`).

## The build, phase by phase

| Phase | Concepts | What it adds | Milestone |
|---|---|---|---|
| 0 | `00` | bootstrap: one integer → a real arm64 exe | M0 |
| 1 | `01–04` | minimal: lexer, parser, sema, LLVM codegen | M1 |
| 2 | `05–09` | types & control flow, functions, **SIL + SILGen + IRGen** (it runs!) | M2 |
| 3 | `10–14` | value types: structs, enums, pattern matching, optionals, layout | M3 |
| 4 | `15–20` | the optimizer: pass manager, **mem2reg/SSA**, fold, GVN, inline, LLVM `-O2` | **M4 — 129% of `swiftc -O`** |
| 5 | `21–24` | generics & protocols: witnesses, erasure, existentials, specialization | **M5 — 104%** |
| 6 | `25–28` | classes & ARC: vtables, retain/release, ownership SSA, ARC-opt | **M6 — 126%** |
| 7 | `29–32` | closures, errors, stdlib: `Array`/`String` (CoW), `map`/`filter`/`reduce` | M7 |
| 8 | `33–40` | from-scratch ARM64 backend (isel, regalloc, ABI, peephole, DWARF); async, actors, macros | **M8 — regalloc ~2.9× over naive** |

Each phase links its own binary: `swiftml` (Phase 1) … `swiftml9`. The newest, **`swiftml9`**, is the
most complete (the full-language LLVM path); **`swiftml8`** is the native ARM64 backend.

## Quick start

Requires macOS/arm64, an opam OCaml switch (5.4+ / dune 3.2+), and Apple's `swiftc` 6.3.x (for the
oracle). Run everything from `course/`.

```sh
cd course
make setup        # opam switch + deps (dune, alcotest, ocamlformat)
make build        # build every phase binary
```

**Compile and run a Swift program** (the shipped tree is *RED by design* — a phase binary is fully
functional once that phase's `solution/` files are in place; `comparisons/run.sh` does that for you):

```sh
echo 'print(6 * 7)' > demo.swift
dune exec swiftml9 -- build demo.swift -o demo   # compile
./demo                                           # => 42
dune exec swiftml9 -- build -O demo.swift -o demo

# inspect any IR — each flag stops at one pipeline stage:
dune exec swiftml9 -- --emit-tokens demo.swift   # Lexer
dune exec swiftml9 -- --emit-ast    demo.swift   # Parser
dune exec swiftml9 -- --typecheck   demo.swift   # Sema
dune exec swiftml9 -- --emit-sil    demo.swift   # SILGen
dune exec swiftml9 -- --sil-opt     demo.swift   # -O passes
dune exec swiftml9 -- --emit-llvm   demo.swift   # IRGen

# Backend B — the from-scratch ARM64 path:
dune exec swiftml8 -- --emit-asm     demo.swift
dune exec swiftml8 -- build --native demo.swift -o demo && ./demo
```

**Work a concept** (RED on the skeleton, GREEN with the solution swapped in):

```sh
make lab C=phase4-optimizer/16-mem2reg-ssa            # a concept's tests
make oracle F=tests/programs/arith.swift B=swiftml4   # diff a program vs swiftc
make explainer-pdf C=phase2-types-flow/08-sil-silgen  # render its lesson
```

**Run the whole-program comparison suite** (31 classical programs vs `swiftc`, `-Onone` and `-O`):

```sh
bash comparisons/run.sh
```

## How a concept is organized

Every concept folder has the same shape (template in `course/_TEMPLATE-concept/`):

```
NN-concept/
├── README.md       # objective, the version ladder, definition of done
├── explainer.qmd   # THE LESSON — a from-zero tutorial (9 sections) + rendered PDF
├── <stage>.ml      # THE SOURCE YOU EDIT — ships as a skeleton with TODO holes
├── solution/       # the frozen, verified answer key
├── tests/          # cram (FileCheck-style) + alcotest unit tests = the spec
├── figs/           # real diagrams (matplotlib/graphviz), generated, committed
└── bench/          # for perf-relevant concepts
```

The source you edit lives **in the concept dir**, and each concept is a small library depending on
the previous one — so the compiler is assembled stage by stage. Skeletons **carry prior work
forward**; the only hole is the *new* idea.

## Repository layout

```
course/
  phase0-setup/ … phase8-arm64-backend/   # the 41 concepts (00–40)
  comparisons/                             # 31 whole programs, swiftml vs swiftc
  course-map/                              # the pedagogical whole-course map
  tooling/                                 # oracle.sh, filecheck.sh
  PROOFREAD.md                             # a critical review (correctness / opt / pedagogy)
  Makefile
CLAUDE.md     # operating guide — how we work
PLAN.md       # the full curriculum and design decisions
swift/        # Apple's swiftc source — READ-ONLY design oracle (git-ignored, ~1.6G)
```

## Verifying it works

- **Behavioral parity** vs `swiftc`: identical stdout + exit code (including traps and exit codes)
  on each concept's programs, and across [`course/comparisons/`](course/comparisons/) — **31/31** at
  `-Onone` and `-O`.
- **FileCheck / unit assertions** on the token stream, AST, SIL, LLVM IR, and diagnostics.
- **Perf, measured** and reported honestly (our subset uses wrapping arithmetic and skips some
  checks, which flatters the comparison — each phase's explainer §2 says so): M4 129%, M5 104%,
  M6 126% of `swiftc -O`; the Phase-8 regalloc ladder reaches ~2.9× over naive.

## Where to go next

- The whole-course map and pipeline: **[`course/course-map/explainer.pdf`](course/course-map/)**.
- The full curriculum and decisions: **[`PLAN.md`](PLAN.md)**.
- A concept's lesson, e.g. SSA construction: `course/phase4-optimizer/16-mem2reg-ssa/explainer.qmd`.
- The critical review and open issues: **[`course/PROOFREAD.md`](course/PROOFREAD.md)**.

---

*An educational project. The `swift/` directory is Apple's compiler source, included only as a
read-only reference and excluded from this repository.*
