# START HERE — How to take this course

This is the learner's manual: the global view and the exact loop to follow. (For the full
curriculum see `../PLAN.md`; for the build/working conventions see `../CLAUDE.md`. You don't
need either to *learn* — this guide is enough.)

---

## 1. What you're building (the global view)

**A real Swift compiler, in OCaml, from scratch** — grown one working slice at a time. By the
end it has the same architecture as Apple's compiler:

```
Swift source
   │  lexer            (you hand-write it — char cursor + token DFA)
   ▼
 tokens
   │  parser           (recursive descent + Pratt — like swiftc's lib/Parse)
   ▼
  AST
   │  Sema             (type checking + name resolution)
   ▼
typed AST
   │  SILGen           (lower to SIL — Swift's own SSA IR)
   ▼
  SIL  ── SIL optimizer (mem2reg, inlining, specialization, ARC opt, …)  ◄── the spine
   │  IRGen
   ▼
LLVM IR ──► clang ──► arm64 executable                      (Backend A)
   │
   └─(Phase 8) our ARM64 backend: isel → register allocation → machine code  (Backend B)
```

The thread through every phase: **start naive and correct, then make it fast — and prove both,
against the real `swiftc`, at every step.**

You build it as a **tower of vertical slices**. Phase 1 is a *complete* compiler for integer
arithmetic + `print`. Each later phase widens the language (types, control flow, functions,
structs/enums, generics, classes+ARC, closures, a stdlib) and deepens the machinery (its own IR,
a real optimizer, two backends) — but you *always* have a compiler that builds and runs.

---

## 2. The two reference compilers (your answer keys)

You never guess what Swift should do — you check against the real thing:

| Oracle | What | How you use it |
|---|---|---|
| **`swiftc`** (installed) | the real toolchain | Compile the same program with `swiftc` and your `swiftml`; they must print the same thing and exit the same way. `make oracle F=…`. |
| **`../swift/`** (source) | Apple's compiler code | When a concept mirrors swiftc (the parser, SILGen, the ARC optimizer…), read the matching `lib/…` file to see how the pros did it. Read-only. |

Both are **read-only**. They are the spec and the answer key — not code you change.

---

## 3. How every concept is organized

Each concept is one self-contained directory, e.g. `phase1-minimal/01-lexer/`:

| File / dir | What it's for |
|---|---|
| `README.md` | The concept at a glance: objective, the version ladder, "definition of done." |
| `explainer.qmd` | **The lesson — read it first.** A full tutorial: concepts in depth (with diagrams), a step-by-step build, how to run the tests, exercises. Renders to PDF/HTML with Quarto (§5). |
| `<stage>.ml` | **The source you edit** — e.g. `01-lexer/lexer.ml`. It ships with `failwith "TODO"` skeletons you fill in. Plus any contract it introduces (`token.ml`, `ast.ml`). |
| `dune` | Makes this stage a small library depending on the previous stage — that's the "step by step" wiring. |
| `tests/` | How you *know* it's right — `FileCheck`-style cram tests + `alcotest` unit tests + parity vs `swiftc`. The tests are the spec. |
| `bench/` | How you *see* the speedup — compile throughput + generated-code runtime vs `swiftc`. |
| `solution/` | The verified answer key for this stage's module(s). Peek when stuck. |

The source you edit lives **right in the concept dir** (`01-lexer/lexer.ml`, `02-parser/parser.ml`,
…). Each concept is a stage-library depending on the previous one; the phase's `bin/` links them
into the **`swiftml`** binary — so the compiler is assembled stage by stage. "swiftml" is the binary
you build, not a separate folder.

---

## 4. The loop — how to actually proceed through a concept

For each concept, in order:

1. **Read the `README.md`** (1 min) and the **explainer** §1–2 for the mental model — render it
   (§5) or just read the `.qmd`.
2. **Fill in the skeleton.** Open the `.ml` file in the concept dir (the functions that
   `failwith "TODO (NN): …"`), and implement them following the explainer's **"Build it"** section
   — it gives the types, APIs, examples, and tips, *not* the answer.
3. **Test your work** — red turns green as you implement:
   ```bash
   make lab C=phase1-minimal/01-lexer
   ```
4. **Check parity** against the real compiler:
   ```bash
   make oracle F=tests/programs/arith.swift
   ```
5. **Stuck?** Read the explainer's **Appendix** (full commented solution) or the matching
   `../swift/lib/…` file, or `solution/`. Try first — the struggle is the learning.
6. **Run the bench** (perf concepts) — see the payoff:
   ```bash
   make bench C=phase4-optimizer/20-llvm-opt
   ```
7. **Move on** when the concept's *definition of done* (in its README) holds — `make lab` green,
   parity matches `swiftc`, any perf gate met.

> The tests are the spec. If you're unsure what a function should do, read its test. `solution/`
> is the answer key; `../swift/lib/…` is how the professionals did it.

---

## 5. Rendering the explainers (Quarto → PDF / HTML)

The explainers are `.qmd` (Quarto markdown). They render to a **PDF** (Quarto's built-in Typst
engine — no LaTeX needed) and a browsable **HTML** page.

**One-time install** (run it yourself — the installer may ask for your password):
```
! brew install --cask quarto
```
*(In Claude Code, the `!` prefix runs it in this session. No-sudo alternative: download the macOS
`.tar.gz` from https://quarto.org/docs/get-started/ and add its `bin/` to your PATH.)*

```bash
make explainer C=phase1-minimal/01-lexer       # → explainer.html
make explainer-pdf C=phase1-minimal/01-lexer   # → explainer.pdf (Typst)
make docs                                   # render every concept
make preview                                # live-preview in the browser
```

You don't *have* to render — the `.qmd` files are plain readable markdown — but the PDF/HTML look
much nicer (typeset math, ToC, syntax highlighting, diagrams).

---

## 6. Setup (one-time — this is Phase 0)

```bash
cd course
make setup        # installs OCaml (opam switch) + dune, alcotest, ocamlformat
make build        # dune build — compiles swiftml
make test         # the fast test subset
```
`make setup` walks you through installing opam if it's missing (`brew install opam` then
`opam init`). See `phase0-setup/00-setup/README.md` for the full bootstrap and the first
end-to-end "exit code" milestone (M0).

> Heads-up: the concept-dir stage modules are **skeletons** —
> your very first task (Phase 0) is to get them to build and turn the first oracle test green.

---

## 7. Running and checking code

```bash
make build                              # compile the compiler
dune exec swiftml -- build foo.swift    # compile a program → ./foo, then run it
dune exec swiftml -- --emit-tokens foo.swift   # inspect the lexer
dune exec swiftml -- --emit-ast foo.swift      # inspect the parser
dune exec swiftml -- --emit-sil foo.swift      # inspect SIL          (Phase 2+)
dune exec swiftml -- --emit-llvm foo.swift     # inspect LLVM IR
dune exec swiftml -- --emit-asm foo.swift      # inspect native asm   (Phase 8)

make test          # ALL concept tests — RED by design on the shipped skeletons
make test-all      # everything
make lab C=<dir>   # just this concept's tests, against your in-progress swiftml
make oracle F=<prog.swift>   # differential: swiftml vs swiftc, same program
make lint          # ocamlformat check (needs `opam install ocamlformat`)
```

`make test` runs every concept's tests in every phase. On the shipped tree that is RED by
design — skeleton TODOs fail their own tests — so day-to-day you run one concept's tests with
`make lab C=<concept>`; its cram tests build `./lab.exe` from that concept's own library, so
they go green when *your* code in that directory is correct

---

## 8. Knowing where you are (milestones)

The big checkpoints, in order (full list in `../PLAN.md` §7):

- **M0** — `swiftml` compiles a trivial program to a real executable; exit-code parity vs `swiftc`.
- **M1** — minimal language (int arithmetic + `print`): full stdout parity.
- **M2** — types, control flow, functions — compiling through your own **SIL**.
- **M3** — structs, enums, optionals, pattern matching.
- **M4** — the optimizer: `swiftml -O` competitive with `swiftc -O`.
- **M5** — generics & protocols + specialization.
- **M6** — classes + ARC + the ARC optimizer.
- **M7** — closures, errors, and a minimal stdlib (`Array`/`String`/`Dictionary`).
- **M8** — the from-scratch ARM64 backend across the whole corpus; the compiler is "complete."

A concept is **done** when its tests pass, it matches `swiftc`, any perf gate is met, and
(optionally) its explainer renders. Then move to the next.

---

## 9. Map of the repo

```
../PLAN.md            full curriculum (every phase, concept, version, check)
../CLAUDE.md          build conventions (mostly for tooling / the AI assistant)
GUIDE.md              ← you are here
README.md             one-paragraph orientation + commands
phase0-setup/         a self-contained M0 compiler (the `swiftml-m0` binary)
phase1-minimal/       Phase 1 = a complete compiler; each concept dir is one stage:
  01-lexer/ … 04-codegen/    the source you edit + tests + solution + explainer
  bin/                       assembles the `swiftml` binary from the four stages
phase2-types-flow/ …  later phases — same shape, bigger language (their own `swiftml`)
tooling/              oracle-vs-swiftc, FileCheck-lite, bench harness
tests/programs/       the shared .swift corpus (grows each phase)
_TEMPLATE-concept/    skeleton for a new concept
../swift/             the real compiler source — read-only design oracle
```

---

## 10. If you get stuck

- **The tests are the spec.** Read the failing test to see exactly what's expected.
- **`swiftc` is the answer key for behavior.** `make oracle F=…` shows exactly how the real
  compiler treats your program; match it.
- **`../swift/lib/…` is the answer key for design.** When you build the parser, read `Parser.cpp`;
  when you build the ARC optimizer, read `lib/SILOptimizer/ARC/` and `docs/SIL/ARCOptimization.md`.
- **Start each version from the previous one.** The ladder is designed so each rung is a small,
  understandable change.

---

## 11. Begin now

```bash
cd course
make setup
```
Then open `phase0-setup/00-setup/README.md` and follow the loop in §4. Phase 0 is tiny on
purpose — it's where you learn the *rhythm* (read → fill skeleton → `make lab` → `make oracle`)
and get the whole pipeline running end-to-end on a one-integer program.
