# PLAN — Build the Swift Compiler from Scratch, in OCaml

A multi-phase, learn-by-doing curriculum. You are a pro coder (new to Swift), so every
concept is taught as a **progressive ladder of implementations** (`v0_naive → … → vN_optimized`),
each automatically checked against the **real Swift compiler**, with **optimization treated as a
first-class, measured goal** — not an afterthought.

The structure is a **tower of vertical slices**: each phase is a *complete, working compiler*
for a growing subset of Swift — lexer → parser → type-checker → IR → optimizer → machine code →
linked executable. Phase 1 compiles a tiny subset end-to-end; by the last phase we have a
real compiler with the same architecture as Apple's: **Parse → Sema → SILGen → SIL optimizer →
IRGen → LLVM → native**, plus our own from-scratch ARM64 backend.

The approach is the classic *incremental* one (Ghuloum, *An Incremental Approach to Compiler
Construction*) — always have a runnable compiler, grow the language one slice at a time —
married to the real Swift compiler's pipeline and the metalgrad course's optimization-ladder
discipline.

---

## 0. Principles

1. **Real artifacts, not toys.** A real compiler with the real architecture (follow the
   `swift/` source), emitting real native executables, validated against the real `swiftc`.
2. **Always a working compiler.** Each phase is an end-to-end vertical slice that compiles and
   runs. We never have a half-built pipeline — we have a complete compiler for a smaller language.
3. **Learn by doing, one concept per directory.** Each concept dir = an explainer + progressive
   implementations + tests + benchmarks.
4. **Progressive optimization.** Like siboehm's CUDA-MMM article but for a compiler: each
   component starts naive/correct and climbs (lexer table-driven, parser error-recovery,
   register allocator stack→linear-scan→graph-coloring, each optimizer pass measured).
5. **Optimization is the spine, not a chapter.** SSA, the pass manager, inlining, generic
   specialization, ARC optimization, devirtualization, instruction selection, register
   allocation, scheduling — these *are* the compiler. Two phases are dedicated deep-dives, and
   every backend concept has a measured ladder.
6. **Everything is checked automatically.** Behavioral parity vs `swiftc` (stdout/exit-code on a
   shared program corpus), `FileCheck`-style assertions on emitted IR/SIL/diagnostics, and
   compile-time + generated-code-runtime benchmarks vs `swiftc -Onone`/`-O`.
7. **Two-level oracle.** `swift/` (the source) is the **design oracle** we read to learn the
   reference implementation; `swiftc` (the installed toolchain) is the **behavioral oracle** we
   differentially test against. Both are **read-only**.

---

## 1. The two oracles (READ-ONLY)

| Oracle | What it is | How we use it |
|---|---|---|
| **`swift/`** (this repo's source) | Apple's real Swift+LLVM compiler, pinned to a 2026-05 snapshot | **Design oracle.** Read `lib/Parse`, `lib/Sema`, `lib/SILGen`, `lib/SILOptimizer`, `lib/IRGen`, and `docs/SIL/`. We mirror its architecture and study how it solves each problem. Never edited. |
| **`swiftc`** (`/usr/bin/swiftc`, 6.3.2) | The installed Swift toolchain | **Behavioral oracle.** Compile the *same* `.swift` program with `swiftc` and with `swiftml`; assert identical stdout / exit code. Also the **perf baseline** (`-Onone` and `-O`) our generated code chases. |

Key reference files in `swift/` (the design oracle):

- **Parse/Lex:** `lib/Parse/{Lexer.cpp,Parser.cpp,ParseExpr.cpp,ParseDecl.cpp,ParseStmt.cpp}`,
  `include/swift/Parse/`, `include/swift/AST/` (the AST node defs).
- **Sema (type checking):** `lib/Sema/{TypeCheckDecl,TypeCheckExpr,TypeCheckConstraints,
  CSGen,CSSolver,TypeCheckPattern}.cpp` (Swift uses **constraint-based** inference).
- **SILGen:** `lib/SILGen/` (AST → SIL), `docs/SIL/SIL.md` (the SIL language), `lib/SIL/`.
- **SIL optimizer:** `lib/SILOptimizer/{Mandatory,Transforms,SILCombiner,ARC,IPO,
  LoopTransforms,FunctionSignatureTransforms,PassManager,Utils,Analysis}/`,
  `docs/SIL/{ARCOptimization,Ownership}.md`, `docs/OptimizerDesign.md`,
  `docs/HighLevelSILOptimizations.rst`.
- **IRGen (SIL → LLVM IR):** `lib/IRGen/`.
- **Runtime/ABI:** `stdlib/public/runtime/` (ARC, metadata), `docs/ABI/`.

Our work lives only under `course/`. The `swift/` tree is a library to read, never to change.

---

## 2. Repository layout

```
/Users/elucterio/Compiler/
├── PLAN.md                     # this file — the curriculum
├── CLAUDE.md                   # operational guide (read every session)
├── course/
│   ├── GUIDE.md                # the learner's manual (start here to learn)
│   ├── README.md               # one-paragraph orientation + commands
│   ├── dune-project            # the OCaml build (dune)
│   ├── Makefile                # task runner (build / test / lab / oracle / bench / docs)
│   ├── phase0-setup/00-setup/  # a self-contained M0 compiler → the `swiftml-m0` binary
│   ├── phase1-minimal/         # Phase 1 = a COMPLETE compiler for the minimal subset
│   │   ├── 01-lexer/           #   token.ml diagnostics.ml lexer.ml  + tests/ solution/ explainer.qmd
│   │   ├── 02-parser/          #   ast.ml parser.ml                  + tests/ solution/ explainer.qmd
│   │   ├── 03-sema/            #   sema.ml                           + tests/ solution/ explainer.qmd
│   │   ├── 04-codegen/         #   irgen.ml driver.ml                + tests/ solution/ explainer.qmd
│   │   └── bin/main.ml         #   assembles the `swiftml` binary from the four stage libraries
│   ├── phase2-types-flow/      # Phase 2 = a complete compiler for a bigger subset (+ SIL), same shape
│   │   └── 05-types-inference/ 06-control-flow/ 07-functions/ 08-sil-silgen/ 09-sil-to-llvm/ bin/ (`swiftml2`)
│   ├── phase3-value-types/     # Phase 3 = structs, enums/ADTs, pattern matching, optionals
│   │   └── 10-structs/ 11-enums-adts/ 12-pattern-matching/ 13-optionals/ bin/ (`swiftml3`)
│   ├── phase4-optimizer/       # Phase 4 = the SIL optimizer (SSA, folding, GVN, inlining) + LLVM -O2
│   │   └── 15-pass-manager/ 16-mem2reg-ssa/ 17-constfold-dce/ 18-cse-gvn/ 19-inlining/ 20-llvm-opt/ bin/ (`swiftml4`)
│   ├── phase5-generics/        # Phase 5 = protocols/witness tables, generics, existentials, specialization
│   │   └── 21-protocols-witness/ 22-generics/ 23-existentials/ 24-specialization/ bin/ (`swiftml5`)
│   ├── tooling/                # oracle-vs-swiftc, FileCheck-lite, bench harness
│   ├── tests/programs/         # shared .swift corpus (grows each phase)
│   └── _TEMPLATE-concept/      # skeleton for a new concept dir
└── swift/                      # ORACLE (read-only) — the real compiler source
```

The compiler we build is named **`swiftml`** (Swift + the ML/OCaml family; placeholder, rename
freely). Following the metalgrad model, **each concept directory is self-contained**: the source
file(s) you edit live right there, next to that concept's `tests/` and a frozen `solution/` answer
key. Each concept is a small **dune library that depends on the previous one** (lexer ← parser ←
sema ← codegen), and a phase's `bin/` assembles those stage libraries into that phase's `swiftml`
binary — so the compiler is built **stage by stage**, the library dependency graph mirroring the
pipeline. Each **phase** is itself a complete, self-contained compiler for its subset; a later
phase extends the previous one. "swiftml" is therefore the *binary you build*, not a separate
source folder.

---

## 3. Concept-directory convention

Every concept lives in its own dir under `course/phaseN-<name>/NN-concept/`:

```
NN-concept/
├── README.md         # objective, prerequisites, the version ladder, definition of done
├── explainer.qmd     # THE LESSON (see §3.1) — Quarto → explainer.pdf (+ HTML)
├── <stage>.ml        # THE SOURCE YOU EDIT — e.g. lexer.ml (+ any contracts it introduces)
├── dune              # makes this stage a library that depends on the previous stage
├── figs/             # make_figs (matplotlib/graphviz) → real diagrams embedded in the explainer
├── tests/            # cram (.t) FileCheck-style + alcotest unit tests; the spec for the concept
├── bench/            # compile-time + generated-code runtime vs swiftc (perf-relevant concepts)
└── solution/         # verified reference snapshot of this stage's module(s) — the answer key
```

- **The source you edit lives right here in the concept dir** (`lexer.ml`, `parser.ml`, …), not in
  a separate folder. Each concept is a small dune library depending on the previous stage; the
  phase's `bin/` links them into the `swiftml` binary. `solution/` is a frozen, verified copy of
  this stage's module(s) — the answer key to diff against (dune ignores it via `(dirs … \ solution)`).
- **Skeleton-to-fill:** each stage's module ships its not-yet-built functions as
  `failwith "TODO (NN): …"` with guiding comments + a pointer to the relevant `swift/` source. You
  replace the TODOs, guided by the explainer; `solution/` is there when you're stuck.
- **Progressive versions are the point.** Where a component has an optimization ladder, the
  explainer walks `v0 → … → vN` and the concept keeps each rung runnable (e.g. the register
  allocator's `solution/regalloc_v0_stack.ml`, `…_v1_linscan.ml`, `…_v2_graphcolor.ml`). Don't
  collapse the ladder — each rung is a teachable, benchmarkable step.

### 3.1 The explainer is the lesson (REQUIRED structure)

`explainer.qmd` is the heart of every concept — a full tutorial a learner can enter from zero and
do the work from alone. Every explainer has these sections (template in
`course/_TEMPLATE-concept/explainer.qmd`):

1. **What you'll build, and why** — objective, prerequisites, outcome, out-of-scope.
2. **Concepts in depth** — thorough teaching with **real diagrams** + the relevant theory + worked
   examples; reference how `swift/` solves it (the bulk of the lesson).
3. **Build it, step by step** — a guided lab pointing at the skeleton in the concept dir: which
   function, what it must do, the types/API to use **with a short example and tips — NOT the full
   code.**
4. **Test it** — `make lab C=<dir>`; what each test checks; the `FileCheck`/oracle assertions;
   expected output.
5. **Benchmark it** — command, expected numbers, interpretation vs `swiftc -Onone`/`-O` (perf
   concepts).
6. **Exercises** — "try it yourself" tasks.
7. **Recap & what's next** — takeaways + bridge to the next concept.
8. **Appendix — full solution** — the complete, heavily-commented answer (mirrors `solution/`),
   with a short explanation (+ diagram) of the hard part.
9. **Exercise solutions** — a worked answer for every exercise.

Render with `make explainer C=phase1-minimal/01-lexer` (Quarto, Typst PDF engine — no LaTeX).

---

## 4. Testing & performance gates

- **Behavioral parity (the headline test):** for a program in `course/tests/programs/`, compile
  with both `swiftml` and `swiftc`, run both, assert **identical stdout and exit code**. This is
  the compiler analog of metalgrad's logit/grad parity. Harness: `course/tooling/oracle.sh`.
- **IR / SIL / diagnostics assertions:** `FileCheck`-style cram tests assert the *shape* of
  `--emit-tokens`, `--emit-ast`, `--emit-sil`, `--emit-llvm`, and diagnostic output. Harness:
  `course/tooling/filecheck.sh` (and real LLVM `FileCheck` if installed).
- **Unit tests:** `alcotest` for component-level checks (lexer token streams, parser ASTs,
  type-checker judgments, individual optimizer passes: "this `.sil` in → that `.sil` out").
- **Perf gates (perf-relevant concepts):** `bench/` emits **compile throughput** (lines/sec,
  passes/sec) and **generated-code runtime**. CI asserts (a) correct, (b) `vK` faster than
  `v(K-1)` where there's a ladder, (c) generated-code runtime within a target band of
  `swiftc -O` on a microbenchmark suite.
- **Markers / dune profiles:** `slow`, `oracle` (needs `swiftc`), `expensive`, `native` (ARM64
  backend). The fast default subset skips the heavy ones — mirror swift's `lit` feature flags.
- **Differential fuzzing (later):** generate random programs in the supported subset, compile
  with both compilers, diff behavior — finds parser/sema/codegen divergences automatically.

**Definition of done (per concept):** parity tests pass against `swiftc`; `FileCheck`/unit
assertions pass; for perf concepts the perf gate is green (`vK` beats `v(K-1)`, generated code
within the target band of `swiftc -O`); the explainer renders with figures from real runs.
Never claim done without running the tests and the oracle. Report perf honestly.

---

## 5. Backend roadmap (the two-backend spine)

Core ladder, built in order:

**Frontend (all phases):** hand-written **lexer** (char cursor + token DFA) and **recursive-descent
+ Pratt parser** (mirroring `lib/Parse`), then a **type checker** (start simple, grow toward
Swift's constraint-based solver).

**Backend A — LLVM (the faithful spine, from Phase 1):**
`AST → (our) SIL IR → (our) SIL optimizer → LLVM IR (text) → clang → arm64 executable`.
Phase 1 lowers AST directly to LLVM IR to get end-to-end fast; Phase 2 inserts **SIL** (our own
SSA IR with Swift-level semantics, per `docs/SIL/SIL.md`) as the place all Swift-specific
optimization happens — exactly as in real swiftc. clang handles final instruction
selection / register allocation / assembly.

**Backend B — native ARM64 (the from-scratch track, Phase 8):**
`SIL → (our) instruction selection → (our) register allocation → arm64 machine code → as/ld`.
A second backend that bypasses LLVM, so we learn instruction selection, register allocation
(stack → linear-scan → graph-coloring ladder), the AAPCS64/Apple calling convention, stack
frames, peephole optimization, and instruction scheduling. Differentially tested against both
the LLVM path and `swiftc`. (This is the analog of metalgrad deliberately learning more than one
GPU backend.)

We target **arm64-apple-macosx** (Apple Silicon). `clang` drives assembly+linking for Backend A;
`as`/`ld` (or `clang` as the driver) for Backend B. Optional: `brew install llvm` to get
`llc`/`opt`/`FileCheck` and, later, OCaml's `llvm` bindings for a programmatic Backend A.

---

## 6. The phases (the tower of vertical slices)

Each phase is a complete compiler for a larger subset. The **Architecture** column shows what
new compiler machinery the phase introduces; the **Subset** column shows the new Swift it accepts.

### Phase 0 — Toolchain & the harness ("hello, exit code")
*Goal: prove the whole loop end-to-end on the most trivial language.*

| Dir | Concept | What you build | Checked against |
|---|---|---|---|
| 00-setup | opam/dune project, the `swiftml` CLI skeleton, the oracle + FileCheck harness, CI | a `swiftml build` that lowers a single integer program to LLVM IR, links via clang, runs | `swiftc`: exit code parity |

**Subset:** a program that is one integer literal (its value becomes the exit code).
**Milestone M0:** `swiftml build prog.swift && ./prog; echo $?` matches `swiftc`; one oracle test green; CI runs it.

### Phase 1 — A minimal compiled language
*Goal: the first real vertical slice — arithmetic you can print.*

| Dir | Concept | Progression | Checked against |
|---|---|---|---|
| 01-lexer | Hand-written lexer: char cursor, token DFA, source locations, trivia, comments | v0 naive scan → v1 table/perf-driven | token-stream unit tests; lexer throughput bench |
| 02-parser | Recursive-descent statements/decls + **Pratt** expressions (precedence, parens, unary) | v0 parse → v1 **error recovery** + good diagnostics | AST unit tests; diagnostic FileCheck |
| 03-sema | Trivial type check (all `Int`), name resolution for `let`/`var`, constant scopes | v0 → v1 | rejects ill-typed programs like `swiftc` does |
| 04-codegen | AST → **LLVM IR** (text), the driver: invoke clang, link, run; diagnostics plumbing | v0 stack-machine IR → v1 simple value-numbering | **stdout/exit parity vs `swiftc`**; IR FileCheck |

**Subset:** `Int` literals & arithmetic (`+ - * / %`, precedence, parens, unary `-`), `let`/`var`,
`print(_:)`, top-level statements, `//` and `/* */` comments.
**Milestone M1:** every program in the Phase-1 corpus matches `swiftc`'s output.

### Phase 2 — Types, control flow, functions (introduce **SIL**)
*Goal: a real type checker and Swift's real IR layer.*

| Dir | Concept | Progression | Checked against |
|---|---|---|---|
| 05-types-inference | `Bool`/`Double`/`String`, **bidirectional** type checking, `let x = e` inference, operator typing, coercions | v0 → v1 | sema unit tests; parity |
| 06-control-flow | `if/else`, `while`, `for i in a..<b`, `break`/`continue`, short-circuit `&&`/`\|\|` | v0 → v1 | parity on control-flow corpus |
| 07-functions | `func` (params, return, overloading-lite), calls, recursion, the call ABI | v0 → v1 | parity; recursion (fib) matches |
| 08-sil-silgen | **Introduce SIL** (our SSA IR per `docs/SIL/SIL.md`); SILGen lowers AST → SIL; `--emit-sil` | v0 unstructured → v1 SSA basic blocks | SIL FileCheck vs swiftc's `-emit-sil` shape |
| 09-sil-to-llvm | IRGen: SIL → LLVM IR; mandatory SIL passes (definite-init diagnostic, verifier) | v0 → v1 | parity; DI rejects use-before-init like swiftc |

**Architecture:** the pipeline becomes the real one: `Parse → Sema → SILGen → SIL → IRGen → LLVM`.
**Milestone M2:** functions + control flow compile through SIL; `--emit-sil` is readable and
mirrors swiftc's SIL structure; definite-initialization diagnostics match.

### Phase 3 — Value types & pattern matching
*Goal: structs, enums (ADTs), and Swift's pattern matcher.*

| Dir | Concept | Progression | Checked against |
|---|---|---|---|
| 10-structs | `struct` (stored properties, methods, memberwise/`init`), value semantics, memory layout | v0 → v1 | parity; layout vs swiftc `-emit-ir` |
| 11-enums-adts | `enum` with associated/indirect values, raw values; tagged-union layout | v0 → v1 | parity |
| 12-pattern-matching | `switch` exhaustiveness, patterns (tuple/enum/binding/`where`), `if let`, `guard` | v0 → v1 | exhaustiveness diagnostics match swiftc |
| 13-optionals | `Optional<T>` as an enum, `?`/`!`, optional chaining, `??` | v0 → v1 | parity; nil-unwrap traps match |
| 14-memory-layout | Aggregate layout, copy/destroy "value-witness" hooks (sets up ARC), `@frozen`-lite | v0 → v1 | layout/size parity vs swiftc |

**Milestone M3:** value types + pattern matching + optionals; a small ADT interpreter program
matches swiftc byte-for-byte on stdout.

### Phase 4 — The optimizer I: mandatory + scalar performance passes
*Optimization-as-spine deep-dive #1. Build the pass manager and the core SSA passes.*

| Dir | Concept | Progression | Perf gate |
|---|---|---|---|
| 15-pass-manager | The SIL pass pipeline, analyses, pass dependencies, `--sil-opt`, pass logging | v0 fixed order → v1 dependency-driven | infra; correctness preserved |
| 16-mem2reg-ssa | Promote stack slots to SSA values (mem2reg); dominator tree; phi insertion | v0 → v1 | fewer loads/stores; runtime ↓ |
| 17-constfold-dce | Constant folding/propagation, dead-code & dead-store elimination | v0 → v1 | constant programs fold to a literal |
| 18-cse-gvn | Common-subexpression elimination / global value numbering, simplifyCFG | v0 local → v1 global | redundant work removed; runtime ↓ |
| 19-inlining | Function inlining (cost model, the inliner), then post-inline cleanup | v0 always-inline-leaf → v1 cost-model | matches/approaches swiftc `-O` |
| 20-llvm-opt | Hand off to LLVM's optimizer (`-O2/-O3` via clang); emit optimized SIL + LLVM IR | v0 → v1 | generated-code runtime vs `swiftc -O` |

**Perf gate:** on the microbench suite, optimized generated code reaches a target band of
`swiftc -O`; each pass measurably improves the metric it targets; no behavior changes (parity holds).
**Milestone M4:** `swiftml -O` is competitive with `swiftc -O` on the microbenchmarks.

### Phase 5 — Generics & protocols
*Goal: the heart of Swift's type system, and a flagship optimization (specialization).*

| Dir | Concept | Progression | Checked against |
|---|---|---|---|
| 21-protocols-witness | `protocol`, conformances, **witness tables**, dynamic dispatch through them | v0 → v1 | parity; witness-table layout |
| 22-generics | Generic functions/types, type parameters, where-clauses, the runtime-metadata model | v0 → v1 | parity |
| 23-existentials | Existential containers (boxing `any P`), opening, value-witness tables | v0 → v1 | layout/behavior parity |
| 24-specialization | **Generic specialization** (monomorphize hot generic calls) + **devirtualization** | v0 → v1 | specialized code ≈ hand-written; runtime ↓ |

**Milestone M5:** generic, protocol-oriented programs compile and run with parity; specialization
turns a generic `max`/container into monomorphic code that approaches `swiftc -O`.

### Phase 6 — Reference types & ARC
*Goal: classes, dynamic dispatch, and automatic reference counting + its optimizer.*

| Dir | Concept | Progression | Checked against |
|---|---|---|---|
| 25-classes-vtables | `class`, inheritance, `override`, **vtables**, `init`/`deinit`, dynamic dispatch | v0 → v1 | parity; vtable dispatch matches |
| 26-arc-runtime | A minimal ARC runtime: object headers, `retain`/`release`, heap allocation, `deinit` timing | v0 → v1 | deinit order/count matches swiftc |
| 27-ownership | The ownership SSA model (owned/guaranteed, `copy`/`destroy_value`), exclusivity-lite | v0 → v1 | ownership verifier; parity |
| 28-arc-optimization | **ARC optimization** (retain/release elimination & motion) — a flagship SIL pass | v0 → v1 | fewer retain/release; runtime ↓; parity |

**Milestone M6:** classes + ARC produce identical deinit behavior to swiftc; the ARC optimizer
removes provably-redundant retain/release pairs without changing observable lifetime.

### Phase 7 — Closures, errors & a minimal standard library
*Goal: the features that make programs real, plus a stdlib written in our own subset.*

| Dir | Concept | Progression | Checked against |
|---|---|---|---|
| 29-closures | Closures + capture (thin/thick), capture lists, escaping vs non-escaping, closure ABI | v0 → v1 | parity |
| 30-error-handling | `throws`/`try`/`do-catch`, `Error`, the error-return ABI, `defer` | v0 → v1 | thrown/caught behavior matches |
| 31-stdlib-array-string | `Array`/`String` built on our heap + generics + ARC (copy-on-write-lite) | v0 → v1 | parity; CoW semantics |
| 32-stdlib-collections | `Dictionary`/`Set`/`Range`, `Sequence`/`Collection` protocols, `map`/`filter`/`reduce` | v0 → v1 | parity on collection programs |

**Milestone M7:** real-ish programs — closures over collections, error handling, `Array`/`String`/
`Dictionary` — match `swiftc` on stdout/exit, including value semantics and copy-on-write.

### Phase 8 — The native ARM64 backend & completeness
*The chosen native track: a second backend with no LLVM. Plus the long tail toward "complete."*

| Dir | Concept | Progression | Perf gate / check |
|---|---|---|---|
| 33-arm64-isel | **Instruction selection** SIL → ARM64 (pattern-matched maximal munch), the encoding | v0 macro-expand → v1 pattern-matched | correct asm; differential vs LLVM path |
| 34-register-allocation | **Register allocation** ladder: stack → **linear-scan** → **graph-coloring** + spilling | v0 stack → v1 linscan → v2 graph-color | runtime ↓ each rung; vs LLVM regalloc |
| 35-mc-abi | Machine code & the **AAPCS64/Apple ABI**: stack frames, calls, prologue/epilogue, `as`/`ld` | v0 → v1 | parity via the native backend |
| 36-peephole-sched | Peephole optimization + **instruction scheduling** for the pipeline | v0 → v1 | runtime ↓; approaches LLVM `-O` |
| 37-debug-info | Source locations end-to-end, a DWARF-lite line table, `swiftml`-built `lldb` stepping | v0 → v1 | breakpoints/lines resolve |
| 38-async-await (opt) | `async`/`await`, the coroutine lowering, the cooperative executor | v0 → v1 | parity on async corpus |
| 39-actors (opt) | `actor`, isolation, `@Sendable`-lite | v0 → v1 | parity |
| 40-macros (opt) | Survey + a minimal expression-macro expander; modules/imports; incremental compilation | v0 → v1 | parity; rebuild-only-changed |

**Milestone M8:** the from-scratch ARM64 backend compiles the entire Phase 1–7 corpus correctly
(differential vs both the LLVM path and `swiftc`), with a register-allocation ladder whose top
rung approaches LLVM's runtime. The compiler is **complete** for the targeted Swift subset, with
two working backends.

---

## 7. Milestones

- **M0** — `swiftml` lowers a trivial program to LLVM IR, links, runs; exit-code parity vs `swiftc`; CI green.
- **M1** — minimal language (int arithmetic + `print`): full stdout parity vs `swiftc`.
- **M2** — types, control flow, functions, compiling through our **SIL**; SIL & DI diagnostics match.
- **M3** — value types (struct/enum/tuple/optional) + pattern matching: ADT programs match.
- **M4** — the optimizer: `swiftml -O` competitive with `swiftc -O` on microbenchmarks.
- **M5** — generics & protocols + generic specialization/devirtualization.
- **M6** — classes + ARC + the ARC optimizer (lifetime-preserving retain/release elimination).
- **M7** — closures, error handling, and a minimal stdlib (`Array`/`String`/`Dictionary`, CoW).
- **M8** — the from-scratch ARM64 backend across the whole corpus; the compiler is "complete."
- **Then** — the optional advanced dirs (async/await, actors, macros, modules, incremental),
  differential fuzzing at scale, and self-hosting experiments.

---

## 8. Tooling

- **OCaml 5.x + opam + dune** (set up in Phase 0). Hand-written lexer/parser (no menhir) to mirror
  `lib/Parse`; `alcotest` for unit tests; **dune cram** (`.t`) for `FileCheck`-style integration
  tests; `ppx_deriving`/`ppx_expect` optional. Format with `ocamlformat`.
- **Backend A:** emit **LLVM IR text**, assemble+link with the installed **`clang`**. Optional
  `brew install llvm` for `llc`/`opt`/`FileCheck` and OCaml `llvm` bindings.
- **Backend B (Phase 8):** emit **ARM64** asm/machine code, link with `as`/`ld`/`clang`.
- **Oracles:** `course/tooling/oracle.sh` (build with both `swiftml` and `swiftc`, diff
  stdout/exit); `course/tooling/filecheck.sh` (FileCheck-lite for IR/SIL/diagnostics, or real
  `FileCheck`); `course/tests/programs/` the shared `.swift` corpus.
- **Benchmarks:** `bench/` measures compile throughput and generated-code runtime; perf gates are
  expressed relative to `swiftc -Onone`/`-O`.
- **Explainers:** **Quarto** (Typst PDF engine + HTML), figures from `figs/` (matplotlib/graphviz).

See `CLAUDE.md` for the operational rules (definition of done, how to add a concept/phase,
commands, the two read-only oracles).
