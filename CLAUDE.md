# CLAUDE.md

Operational guide for this repo. Read `PLAN.md` for the full curriculum. This file is the
day-to-day "how we work."

## What this project is

A multi-phase, learn-by-doing build of **the Swift compiler, from scratch, in OCaml** (the user
is a pro coder, new to Swift, who wants depth + real optimization). Each phase is a **complete,
working compiler for a growing subset of Swift**, with the same architecture as Apple's compiler:

```
Parse → Sema → SILGen → SIL → SIL optimizer → IRGen → LLVM → native   (Backend A)
                          └→ (Phase 8) → our ARM64 isel → regalloc → machine code   (Backend B)
```

The compiler we build is named **`swiftml`** (rename freely). We build **two backends**: the
LLVM-IR spine (faithful to swiftc, from Phase 1) and a from-scratch **ARM64** backend (Phase 8).
The lexer and parser are **hand-written** (recursive descent + Pratt), mirroring `lib/Parse`.

## The two oracles are READ-ONLY

- **`swift/`** — Apple's real compiler source (pinned 2026-05 snapshot). The **design oracle**:
  read it to learn the reference implementation; mirror its architecture. **Never edit it.**
- **`swiftc`** (`/usr/bin/swiftc`, 6.3.2) — the installed toolchain. The **behavioral oracle**:
  compile the same `.swift` with `swiftml` and `swiftc`, assert identical stdout/exit. Also the
  **perf baseline** (`-Onone`/`-O`) we chase. Don't try to modify the toolchain.

Our work lives only under `course/`. Key `swift/` reference files are listed in `PLAN.md` §1.
When a concept mirrors a part of swiftc, open the corresponding `lib/…` file and read it.

## How a concept directory is built

Every concept = its own dir under `course/phaseN-<name>/NN-concept/` (template:
`course/_TEMPLATE-concept/`):

```
NN-concept/
├── README.md       # objective, prereqs, the version ladder, definition of done
├── explainer.qmd   # THE LESSON (required 9-section structure — see PLAN.md §3.1)
├── <stage>.ml      # THE SOURCE YOU EDIT (e.g. lexer.ml) + any contracts it introduces
├── dune            # this stage = a library depending on the previous stage's library
├── figs/           # make_figs → real diagrams embedded in the explainer
├── tests/          # cram (.t) FileCheck-style + alcotest unit tests — the concept's spec
├── bench/          # compile-time + generated-code runtime (perf-relevant concepts)
└── solution/       # verified reference snapshot of this stage's module(s) — the answer key
```

**Self-contained concept dirs, assembled stage by stage.** Like metalgrad, the source you edit
lives **in the concept dir** (`01-lexer/lexer.ml`, `02-parser/parser.ml`, …) — not in a separate
folder. Each concept is a small dune library that depends on the previous stage's library
(`swiftml_lexer ← swiftml_parser ← swiftml_sema ← swiftml_codegen`); a phase's `bin/main.ml`
links them into that phase's **`swiftml`** binary. So the compiler is built **stage by stage**, the
library graph mirroring the pipeline. Each **phase** is a complete, self-contained compiler for its
subset (Phase 0 is the self-contained `swiftml-m0`); later phases extend the previous. The stage
modules ship as skeletons (`failwith "TODO (NN): …"` + guiding comments + a `swift/` pointer); you
fill them in. `solution/` is the frozen answer key (kept out of the build via `(dirs … \ solution)`).
"swiftml" is the binary you build, not a source dir.

**Progressive versions are the whole point.** Where a component has an optimization ladder
(register allocator, optimizer passes, instruction selection), keep each rung runnable and
benchmarkable — e.g. `solution/regalloc_v0_stack.ml`, `…_v1_linscan.ml`, `…_v2_graphcolor.ml`.
Don't collapse the ladder. Start naive/correct, then climb (à la siboehm CUDA-MMM).

## Skeletons carry the contract; the explainer carries the lesson

A concept-dir skeleton states **what the function must produce and the properties the tests
enforce**, then points at the explainer section that walks it through — three or four lines, not a
transcription of §3. The learner should be able to open the file and try it cold, with the help one
deliberate click away, instead of having to fold comments away to avoid reading the answer. Two
rules make that safe:

- **No information may be lost.** Anything trimmed from a skeleton must already exist in the
  explainer (spec in §3/§5, code in §8) — check before deleting, and move it if it doesn't.
- **Comments on GIVEN code stay.** The cursor helpers, the contracts, the `push`/`skip` machinery
  the learner never edits: those comments are documentation, not hints, and they earn their place.

Applied to 01-lexer and 02-parser (2026-08-23); the older concepts still carry inline walk-throughs.

## The explainer is the lesson (REQUIRED)

`explainer.qmd` is a full tutorial, never a stub. A learner enters from zero and can do the work
from it alone. Required sections (see `PLAN.md` §3.1 and `_TEMPLATE-concept/explainer.qmd`):
**1** what/why · **2** concepts in depth (diagrams + theory + how swiftc does it; the bulk) ·
**3** build it step-by-step (skeleton + API + tips, **not** the answer) · **4** test it ·
**5** benchmark it · **6** exercises · **7** recap & next · **8** appendix full solution ·
**9** exercise solutions. Diagrams are **real figures** from `figs/` (matplotlib/graphviz),
embedded with `![](figs/x.png)`. Render: `make explainer C=<dir>`.

**Keep code-block lines short.** The explainers are mostly code, and a line that does not fit is
worse than a line that is split: in the PDF it wraps mid-expression, losing the indentation that
carries the meaning. Budget is **92 characters** (the prose wraps at 100); the PDF fits ~107 at its
7.6pt code size, so 92 leaves room. Reflow at argument or `;` boundaries rather than shrinking type.

**Always generate the figures — never leave a stub.** If an explainer references `figs/x.png`, that
concept ships a `figs/make_figs.py` that produces it, and the PNG is generated and committed in the
same change. No "(figure to be generated)" placeholders, ever — they read as done but break the
Typst/PDF render (HTML silently tolerates a missing image; PDF hard-fails). `make explainer` and
`make explainer-pdf` run the `figs` target first (via the project `.venv` + matplotlib) so figures
are always current. A concept isn't done (DoD #4) until its figures come from a real run *and* both
HTML and PDF render clean.

## Definition of done (per concept / version)

A concept is done only when **all** hold:
1. **Behavioral parity** against `swiftc` on the concept's programs (identical stdout + exit code).
2. **FileCheck/unit assertions** pass (token stream / AST / SIL / LLVM IR / diagnostics shape).
3. For perf-relevant concepts: the **perf gate** is green — `vK` beats `v(K-1)`, and generated
   code is within the target band of `swiftc -O` on the microbench suite.
4. The explainer (`explainer.qmd`) renders and its figures come from real runs.

Never claim a concept/version is done without actually running its tests and the oracle. Report
perf honestly (compile throughput, generated-code runtime, % of `swiftc -O`). If a gate isn't
met, say so.

## Parity gotchas (matching `swiftc`)

The usual sources of divergence to watch: integer **overflow semantics** (Swift traps on overflow
in `-Onone`; `&+` wraps), **integer division/remainder** sign & trap-on-zero, **`Int`/`Double`
formatting** in `print` (Swift's exact float printing), **trap messages & exit codes** (force-unwrap
nil, out-of-bounds, overflow → specific traps/exit), **evaluation order**, **short-circuit**
`&&`/`\|\|`, **definite-initialization** rules, **deinit timing/order** under ARC, **value vs
reference** semantics (copy-on-write), and **String** Unicode/grapheme behavior. When stdout
differs, suspect one of these first.

## Commands (wire up in `course/`)

**Toolchain is the opam switch.** A Homebrew `dune`/`ocaml` may also be on PATH, but it can't see
opam-installed libs (e.g. `alcotest`), so the `Makefile` runs dune via `opam exec -- dune` and
`oracle.sh` does `eval $(opam env)`. If you call `dune` directly, run `eval $(opam env)` first or
you'll get `Library "alcotest" not found`.

Run from `course/`:
- Setup (Phase 0): `make setup` (opam switch + deps: `dune`, `alcotest`, `ocamlformat`).
- Build everything: `make build` (`dune build`). One binary per phase: `dune exec swiftml|swiftml2|swiftml3|swiftml4 -- <args>`.
- All tests: `make test` — on the shipped tree this is RED **by design** (skeleton TODOs fail
  their own tests); it goes green only with solutions in place.
- One concept's tests: `make lab C=phase4-optimizer/16-mem2reg-ssa`. Each concept's cram tests
  run `./lab.exe`, built from THAT concept's library — so they test the code in that directory,
  not the phase binary. RED on the skeleton, GREEN with `solution/` swapped in.
- Differential vs swiftc: `make oracle F=tests/programs/arith.swift` (`B=swiftml4` to pick a
  later phase's binary).
- Benchmark (concepts with a `bench/`: 01-lexer, 20-llvm-opt): `make bench C=phase4-optimizer/20-llvm-opt`.
- Exercise tests (01-lexer): the §6 exercises run inside `make lab`, each group SKIPPING itself
  until a probe sees the lexer behave differently from stock (a half-done attempt fails, it is
  not skipped); `make exercises C=…` runs only those. Same skip-until-started convention makes
  the `v1_fast` rung optional: `make lab`/`bench`/`profile` all work on v0 alone.
- Profile (01-lexer has `bench/profile.ml`): `make profile C=phase1-minimal/01-lexer` — per-construct
  cost, scan-vs-build ablation ladder, allocation accounting, `Gc.Memprof` allocation sites; and
  `make profile-cpu C=…` (`tooling/profile-cpu.sh`) — macOS `sample` call tree, your code vs the GC.
- Explainers: `make explainer C=<dir>` (HTML) · `make explainer-pdf C=<dir>` (Typst; both re-run
  `figs` first) · `make docs`. Formatting: `make fmt` (needs ocamlformat installed).

The phase CLIs expose inspection flags the tests assert on: `--emit-tokens`, `--emit-ast`,
`--typecheck` (front end only — lex/parse/sema, like `swiftc -typecheck`; lets Sema be tested in
isolation), `--emit-sil` (raw SIL), `--sil-opt` (optimized SIL, phase 4), `--emit-llvm`, `build`,
and `-O` (phase 4: SIL passes + clang -O2; default is the -Onone path). `--emit-asm` arrives with
Backend B (Phase 8).

## Working autonomously (don't over-confirm)

Default to **acting, not asking** — the user wants long, uninterrupted runs and should not have to
sit at the keyboard approving routine steps. Work in long stretches, then report results; don't
checkpoint each step.

- **Just do it, no confirmation:** read/grep/inspect any file; scratch work and throwaway tests
  under `/tmp`; `dune build`/`exec`/`runtest`, `make` targets, cram/alcotest runs, `swiftc`/`clang`
  oracle comparisons, figure generation (`.venv` + matplotlib), benchmarks, explainer renders; the
  temporary swap-and-verify of a `solution/` against the tests; anything trivially reversible.
- **Only stop for the big calls:** architecture/curriculum changes; choosing between materially
  different designs; touching the READ-ONLY `swift/` oracle or the installed toolchain; destructive
  or outward-facing actions (deleting work you didn't create, pushing, publishing); or a genuine
  ambiguity that changes direction. When a sensible default exists, take it and *say so* — don't ask.
- The harness permission allow-rules in `.claude/settings.local.json` are kept **broad** for these
  safe operations so they don't prompt. If a new safe command keeps prompting, widen that allowlist
  (a glob like `Bash(make *)`), don't narrow how much you do.

## Status / honesty notes

- **Lexer diagnostics (2026-08-22) — DONE, whole tree.** `Lexer.create : string -> Diagnostics.sink
  -> t` in all **41** `lexer.ml` copies (skeletons + solutions, phases 1–8): the lexer REPORTS
  (`invalid character in source file`, `unterminated '/*' comment`, `expected '&' after '&'`, …) and
  RECOVERS — drop the byte / stop the comment, keep lexing — instead of `failwith`. Matches the
  oracle: `Lexer.h:150` takes a `DiagnosticEngine *`, `Lexer.cpp` has 59 `diagnose` sites, and
  `DiagnosticsParse.def` defines 35 `lex_*` diagnostics; wording copied from
  `diag::lex_invalid_character` / `diag::lex_unterminated_block_comment`. Every driver bails right
  after lexing, so a bad byte is `line:col: error: …` + **exit 1**, not an OCaml exception + exit 2.
  157 call sites updated (drivers, tests, benches). Concept-01 tests assert wording+span+recovery and
  that BOTH rungs emit identical diagnostics; §6 exercise 2 is now "add the `Note` at the opener"
  (`diag::lex_comment_start`). Verified: clean build, comparison suite **31/31** at -Onone and -O,
  concepts 05/16/26 green with solutions swapped in.
- **Toolchain installed; M0 done.** ocaml 5.4.1 / dune 3.23.1 / opam 2.5.1 (brew). `dune build` is
  clean. Phase 0's self-contained `swiftml-m0` compiles a single integer to a real arm64 exe
  (verified). The Phase-1 stage modules (`lexer.ml`/`parser.ml`/`sema.ml`/`irgen.ml`) ship as
  `failwith "TODO"` skeletons — both the cram tests **and** the alcotest unit tests correctly run
  RED on them. Don't call a stage "working" until its tests + `make oracle` pass.
- **Phase 1 solutions exist and are verified.** All four `solution/*.ml` pass cram + alcotest +
  swiftc-oracle parity (checked by temporarily swapping a solution over its skeleton, never by
  editing the skeleton — that's the learner's). Each `tests/` dir now has a cram `.t` **and** an
  alcotest `test_*.ml` (token kinds/spans, AST structure + diagnostics, exact sema messages, emitted
  IR shape). `Ast` gained an `Assign` node and the driver a `--typecheck` mode (front end only) to
  support reassignment and isolated sema testing.
- **Phase 2 started; concept 05 (`05-types-inference`) is complete and verified.** Its own evolved
  stage library `swiftml_types` + `swiftml2` binary (`--emit-tokens`/`--emit-ast`/`--typecheck`);
  carry-forward skeletons (lexer/parser given for Phase-1 features, `TODO(05)` holes for the new
  lexemes/syntax) + the new **bidirectional type checker** in `sema.ml`. Tests green RED→solution
  (cram + 2 alcotests) and the **type-check oracle matches `swiftc -typecheck`** on a 16-case
  accept/reject corpus. Deep explainer + figure render. Phase 2 libs use `wrapped false` and coexist
  with Phase 1's same-named modules (not linked together).
- **Concept 06 (`06-control-flow`) is complete and verified.** Its own library `swiftml_flow`
  (copy-and-extend of 05; the phase `swiftml2` binary now links the latest, superset library);
  carry-forward skeletons with `TODO(06)` holes for `{ } && || ..<`, the control-flow statements, and
  the sema rules (Bool conditions, **lexical block scoping via a scope stack**, immutable `for` var,
  `break`/`continue` loop-context, `&&`/`||`). Tests green RED→solution (cram + 2 alcotests); the
  type-check oracle matches `swiftc -typecheck` on a 12-case corpus. Deep explainer + CFG figure
  (sets up *why* SIL needs basic blocks).
- **Concept 07 (`07-functions`) is complete and verified.** Library `swiftml_funcs` (bin repointed);
  adds `func`/`return`/`->`, top-level *items*, `TVoid`. The new sema is a **two-pass** check
  (collect signatures → check bodies) so recursion + forward refs work, plus call typing, return
  typing, and the **"missing return"** definite-return analysis. Oracle matches `swiftc -typecheck`
  on 11 cases. **Argument labels are simplified**: we call positionally, so the corpus uses Swift's
  `_` form (`func add(_ a: Int, …)`) — full label checking is deferred. Deep explainer + two-pass
  figure. **Phase-2 front-end is complete.**
- **Concept 08 (`08-sil-silgen`) is complete and verified.** Library `swiftml_sil` (bin repointed).
  Introduces **SIL** (`sil.ml` contract: basic blocks + terminators, alloc_stack/load/store, apply;
  `--emit-sil` printer + verifier) and **SILGen** (`silgen.ml`: AST→SIL). Per the design decided with
  the user: **memory-based raw SIL** (no SSA — mem2reg/SSA is deliberately Phase 4, concept 16, see
  [[teach-ssa-in-phase4]]); recognizable-but-simplified swiftc-SIL syntax. The skeleton's `TODO(08)`
  holes are the **control-flow CFG construction** (if-diamond, while back-edge, for desugar,
  break/continue); the builder API + gen_expr + lower are given. SILGen verified to emit correct SIL;
  tests green RED→solution (cram FileCheck on SIL shape + 6 alcotests). Deep explainer + tree→CFG
  figure.
- **Concept 09 (`09-sil-to-llvm`) is complete — PHASE 2 DONE, Milestone M2 reached.** Library
  `swiftml_llvm`; **IRGen** (`irgen.ml`: SIL→LLVM IR, near 1:1 since both are memory-based + blocks)
  + `--emit-llvm` + `build` (clang→native). **Phase-2 programs RUN and match `swiftc` byte-for-byte**
  (verified: arithmetic, if/else, while/for, break/continue, nested loops, recursion fib, bool).
  Skeleton `TODO(09)` holes = gen_instr + gen_term (the SIL→LLVM mapping); plumbing given. Runtime
  corpus is Int/Bool/control-flow/functions; Double-print & String runtime & definite-init are
  documented simplifications / exercises. **A real runtime bug was caught by running**: the `for`
  loop's `continue` skipped the increment (infinite loop) — fixed with a **latch** block in SILGen
  (08+09); the lesson (behavioral parity catches what structural tests miss) is in the 09 explainer.
  Tests green RED→solution (cram **builds+runs** programs + 5 alcotests). Deep explainer + full-pipeline
  figure.
- **PHASE 3 STARTED. Concept 10 (`phase3-value-types/10-structs`) is complete and verified.** Library
  `swiftml_structs`; binary **`swiftml3`** (phase3-value-types/bin). Adds **`struct`** — Swift's value
  type — through every stage: contracts (types `TStruct`+`struct_layout`; ast struct decl/`Member`/
  labeled `Call` args/`Set_member`; sil `Struct`/`Struct_extract`/`Struct_element_addr` + layouts in
  modul), lexer (`.` Dot, `;`→Newline separator), parser (struct decls, member access, labeled init
  args, `p.x=e`), sema (struct registry PASS 0, member typing, init label/type checks, member assign +
  let-field rejection), silgen + irgen. **Struct programs RUN and match swiftc** incl. **value
  semantics** (`var q=p; q.x=99` leaves `p.x`=1), structs-by-value to functions, nested structs.
  Skeleton `TODO(10)` = the value-type *lowering* (silgen member read=struct_extract/write=struct_
  element_addr; irgen insertvalue/extractvalue/getelementptr); front-end given. Tests green RED→solution
  (cram **builds+runs** struct programs + 4 alcotests). Deep explainer + value-semantics figure. v0 =
  stored properties+init+access+value semantics; **methods/mutating/computed are v1/exercises**.
- **Concept 11 (`phase3-value-types/11-enums-adts`) is complete and verified.** Library `swiftml_enums`
  (bin repointed). Adds **`enum`** — Swift's sum type / tagged union — through every stage: contracts
  (types `TEnum`+`enum_layout`+case helpers; ast enum decl/`IEnum`/`Method_call` for `E.case(args)`;
  sil `Enum`/`Enum_tag` + enums in modul), lexer (`enum`/`case` kw, `;`-sep), parser (enum decls,
  multi-case-per-line `case a,b,c`, `E.case(args)` postfix, `: Int` raw), sema (enum registry in PASS 0,
  case typing, `.rawValue` on raw enums, **Equatable rule**), silgen + irgen. Representation = `{ i64
  tag, i64×maxPayload }` (tag at #0). **Enum programs RUN and match swiftc**: simple-enum `==` (tag
  compare), raw values (`rawValue`=index, verified vs swiftc), enums in `if`/`var`. **Parity matched on
  both sides**: payload-free enum `==` works (implicitly Equatable); associated-value `==` is REJECTED
  ("does not conform to 'Equatable'") like swiftc. Skeleton `TODO(11)` = enum construction (silgen
  Member/Method_call→Sil.Enum) + irgen Enum/Enum_tag (insertvalue/extractvalue); front-end given. Tests
  green RED→solution (cram **builds+runs** + 4 alcotests). Deep explainer + tagged-union figure. v0:
  Int payloads, implicit raws; **destructuring associated values = concept 12 (switch)** — that's why
  enums+pattern-matching are paired. Caught+fixed a real bug: multi-case-per-line ordering was reversed
  (rawValue test) — `List.rev_append cs acc`.
- **Concept 12 (`phase3-value-types/12-pattern-matching`) is complete and verified.** Library
  `swiftml_match` (bin repointed). Adds **`switch`** through every stage: contracts (ast `pattern`
  =`PEnumCase`/`PInt` + `pat_binding` Bind/Ignore, `Switch` stmt; sil `Enum_payload`), token
  (`switch`/`default`), parser (parse_switch/parse_pattern/parse_bindings — `.case(let x)`, `_`, Int
  pats, `default`), sema (`check_switch`: pattern typing + payload binding into the case scope +
  **exhaustiveness**), silgen (the **dispatch lowering**), irgen (`Enum_payload`→extractvalue #i+1).
  **switch programs RUN and match swiftc**: enum destructure w/ bindings (area→12,25,0), a **mini ADT
  interpreter** (eval Op→7,42), Int switch+default, switch-as-stmt. Exhaustiveness reject matches
  swiftc ("switch must be exhaustive"). Extended concept-07's **missing-return** analysis: an
  exhaustive all-returning switch = a definite return (caught when `area` failed to build). Skeleton
  `TODO(12)` = the silgen switch dispatch (enum_tag→cond_br chain→case block binds payload→merge) +
  the sema exhaustiveness check; front-end + pattern-typing given. Tests green RED→solution (cram
  **builds+runs** switch programs + 4 alcotests). Deep explainer + dispatch-CFG figure. v0: single
  pattern/case, no where/tuple/if-let (exercises); linear dispatch (jump-table = exercise). **ADT half
  of Phase 3 done.**
- **Concept 13 (`phase3-value-types/13-optionals`) is complete and verified — Milestone M3.** Library
  `swiftml_optionals` (bin repointed). Adds **optionals** as sugar over the enum engine: `Optional<T>`
  = `enum { none=0; some(T)=1 }`, monomorphized (no generics until Phase 6). Contracts: `Types.TOptional`
  (`{i64 tag, T}`), ast `Nil`/`Force_unwrap`/`Coalesce`/`If_let`, sil **`Trap`** terminator. token (`nil`/
  `?`/`!`), lexer (`!`→Bang unless `!=`, `?`→Question), parser (`T?` via parse_type_name, `e!` postfix,
  `??` infix bp6, `if let`, `nil`), sema (contextual `nil`, **implicit wrap** T→T? via check_expr, unwrap/
  coalesce/if-let rules, `opt==nil`), silgen (reuses Enum/Enum_tag/Enum_payload; `gen_expr_as` for
  wrapping at Let-annot/Return/args/?? ; force-unwrap trap), irgen (`TOptional`→`{i64,T}`, `Trap`→write+
  `@llvm.trap`). **Optional programs RUN and match swiftc**: if let/??/!/==nil, `-> Int?` funcs w/ implicit
  wrap. **Force-unwrap-nil traps EXACTLY like swiftc**: same message + **exit 133** (SIGTRAP via llvm.trap),
  verified. Skeleton `TODO(13)` = the silgen optional lowering (gen_expr_as wrap, Force_unwrap, Coalesce,
  If_let); everything else given. Tests green RED→solution (cram **builds+runs+traps** + 3 alcotests).
  Deep explainer + "optional=enum" sugar-table figure. v0: monomorphic optionals; chaining/`guard let`/`T!`
  = exercises. **Phase-3 value-type story essentially complete; `14-memory-layout` deferred** (user
  pivoted to Phase 4).
- **PHASE 4 STARTED (the optimizer). Concept 15 (`phase4-optimizer/15-pass-manager`) is complete and
  verified.** Library `swiftml_passes`; binary **`swiftml4`** (phase4-optimizer/bin) with `-O` +
  `--sil-opt`. New module **`opt.ml`** = the optimizer spine: a `pass = {name; run: Sil.func->Sil.func}`,
  `run_pipeline` (the pass manager), and two demo passes — **constant_fold** (literal arith → Int_lit;
  guards ÷0/%0 for the runtime trap) + **dead_instr_elim** (drop pure instrs whose result is unused;
  keeps Store/Apply/Print). driver: `-O` runs `Opt.optimize` on the SIL before IRGen; `--sil-opt` prints
  optimized SIL; `--emit-sil` = raw. **Verified**: `print(1+2*3)` raw SIL has 2 binops → `--sil-opt`
  folds to `integer_literal 7` + DCE removes the dead instrs; **`-O` preserves behavior** (matches swiftc
  AND -Onone on arith/fib/loop+struct/enum-switch). Skeleton `TODO(15)` = run_pipeline + constant_fold;
  helpers/DIE/pipeline given. Tests green RED→solution (cram --emit-sil vs --sil-opt + -O runs + 4
  alcotests). Caught a test-aliasing bug (passes mutate in place → measure counts BEFORE optimize) and a
  cram `grep -c`-exits-1-on-0 quirk (|| true). Deep explainer + pipeline figure. **DESIGN DECISIONS for
  Phase 4 (recorded in [[teach-ssa-in-phase4]]): SSA form = basic-block arguments (swiftc's, not phi);
  pass-manager-first-then-mem2reg.** Passes are weak on raw memory-based SIL (can't see through
  load/store) — **that's the motivation for concept 16**.
- **Concept 16 (`phase4-optimizer/16-mem2reg-ssa`) is complete and verified — the SSA lesson (the
  user's most-wanted).** Library `swiftml_mem2reg` (bin repointed). **SIL now carries basic-block
  arguments**: `block.args : (value*ty) list`; `Br of int*value list`; `Cond_br of value*(int*value
  list)*(int*value list)`. Mechanically updated the given SILGen (all Br/Cond_br get empty arg lists,
  blocks get `args=[]`) and **rewrote IRGen** to lower block-args → LLVM **phi** (pre-pass assigns a
  stable `%vN` operand to every value so back-edge/phi incomings resolve; gen_phi emits phis from the
  per-block `incoming` map). **`opt.ml` mem2reg** = the full classic SSA construction: promotable-slot
  detection (alloc_stack used only as load/store ADDRESS), **dominators** (iterative dataflow + idom),
  **dominance frontiers** (Cooper-Harvey-Kennedy), **liveness** (backward dataflow → **pruned SSA**),
  **phi placement** at iterated DF ∩ live, and the **renaming** dominator-tree DFS (thread reaching
  value, replace loads, drop stores, fill branch args). Added to the `-O` pipeline FIRST (so
  constfold/DCE see through memory). **Verified: a loop becomes pure SSA** (`bb1(%i,%s):` block args,
  entry passes `(0,0)`, latch passes `(i+1,s+i)`, zero load/store) and **`-O` preserves behavior** —
  10/10 broad regression vs swiftc+swiftc-O (loops, fib(22), nested loops, structs, multi-payload enum
  switch, optionals, continue). **Real bug caught & fixed: needed pruned SSA (liveness)** — a `let p`
  inside a loop got a spurious header phi → `IMap.find` Not_found on the entry edge; liveness pruning
  fixes it (documented in the explainer). Skeleton `TODO(16)` = the **renaming** walk (the heart);
  analyses + placement given. Tests green RED→solution (cram --emit-sil vs SSA --sil-opt + -O runs + 4
  alcotests). Deep from-zero SSA explainer (dominators/frontiers/liveness/renaming, block-args vs phi)
  + memory→SSA figure. v0: scalar/whole-aggregate slots; SROA/struct-field promotion + trivial-phi
  removal = exercises. Next: `17-constfold-dce` (now powerful on SSA), → 18 cse/gvn, 19 inlining, 20
  llvm-opt; **M4** = swiftml -O ≈ swiftc -O.
- **Concept 17 (`phase4-optimizer/17-constfold-dce`) is complete and verified.** Library `swiftml_constfold`
  (bin repointed). Turns concept-15's toy passes real now that mem2reg gives SSA. `opt.ml`: generalized
  **constant_fold** over a `cst = CInt|CBool` lattice (`fold_binop`: Int arith→Int, 6 comparisons→Bool,
  &&/||→Bool; ÷0/%0→None to keep the runtime trap) + **simplify_cfg** (fold `cond_br` on a const Bool→`Br`
  keeping the taken side's block-args, then dead-block elim = DFS-reachable-from-bb0). `-O` pipeline now
  mem2reg→fold→simplify→fold→simplify→DIE. **Verified**: `3<5`→`Bool true`; `if 10>3{print 1}else{print 2}`
  folds the branch and **deletes the unreachable else block** (whole branch gone); 10/10 broad -O regression
  vs swiftc+swiftc-O (const arith, if-folding, loops, fib(18), struct/enum/optional). Block-args shine again:
  deleting a block auto-removes its phi incomings (no φ-list surgery). Skeleton `TODO(17)` = fold_binop +
  simplify_cfg; the constant_fold driver + mem2reg + DIE given. Tests green RED→solution (cram folds+branch-
  elim+-O runs + 4 alcotests; hit the `grep -c`=0-exits-1 quirk again, `|| true`). Deep explainer (folding
  propagates through SSA; fold-condition→fold-branch→delete-block; iterate; preserve traps) + branch-fold
  figure. Exercises: SCCP, algebraic identities, dead-store elim, block merging+fixpoint. Next: `18-cse-gvn`
  (common-subexpression elimination / global value numbering), → 19 inlining, 20 llvm-opt; **M4** ≈ swiftc -O.
- **Concept 18 (`phase4-optimizer/18-cse-gvn`) is complete and verified.** Library `swiftml_gvn` (bin
  repointed). Adds **GVN** (global value numbering / CSE): `opt.ml` `value_key` (a string key per PURE
  instr — equal keys ⇒ equal values; operands run through `canon`; None for load/store/apply/print/
  alloc_stack/struct_element_addr so they're never CSE'd) + `gvn` (build dominator tree, DFS with a
  **dominance-scoped** key→value table: push expressions entering a block, pop on exit, so a value is
  reused only where its def DOMINATES the use; redundant instr → `repl`/`removed`, then rewrite operands
  via canon). Pipeline: mem2reg→fold→cfg→fold→**gvn**→cfg→DIE. **Verified**: `x*x+x*x` 2 muls→1; CSE
  across a dominated join (`n*2` in cond+both branches) reused; calls NOT merged (impure); 10/10 broad -O
  regression vs swiftc+swiftc-O. Skeleton `TODO(18)` = value_key + the scoped visit; dominator tree +
  commit given. Tests green RED→solution (cram CSE + -O + 4 alcotests incl. value-key + impure-safety).
  Deep explainer (value numbering, what's pure, dominance scoping = local CSE vs global GVN, SSA makes
  rewrite local) + before/after figure. Exercises: commutativity, redundant-load elim, hash-consing,
  congruence GVN. Next: `19-inlining` (replace a call with the body; creates new fold/CSE/DCE work),
  then `20-llvm-opt`; **M4** = swiftml -O ≈ swiftc -O.
- **Concept 19 (`phase4-optimizer/19-inlining`) is complete and verified.** Library `swiftml_inline` (bin
  repointed). Adds **function inlining** — the first INTER-procedural pass (module-level, run before the
  per-function pipeline in `optimize`). `opt.ml` `inline_module`: for a call `%r=apply @f(args)` whose
  callee f is a **single-block LEAF** (1 block, no Apply inside, not main), splice f's body at the call:
  `vmap` = param→actual-arg else +offset; renumber f's instrs (copy types into caller val_ty); splice in
  place of the apply; the call result rv → f's return value everywhere; finally drop now-uncalled functions
  (count only Apply, not dead func_refs — else the inlined-away callee lingers). **Verified**: `sq(5)`
  inlined→`5*5`→folds to `25`, `@sq` removed; 8/8 broad -O regression incl. nested calls, inline-in-loop,
  and recursive fib correctly NOT inlined (has Apply → not a leaf) + multi-block `clamp` NOT inlined (>1
  block). The payoff = the CASCADE (inline exposes args/results so fold/CSE/DCE run across the old call
  boundary). Skeleton `TODO(19)` = the inline transform (vmap/splice/return-sub); the worklist + inlinable
  check + dead-fn removal given. Tests green RED→solution (cram inline+fold+remove + -O + 4 alcotests incl.
  recursive/multiblock kept). Dedup note: hit a dune build-race in RED/GREEN (transient exit=1; clean
  re-run = RED1/GREEN0). Deep explainer (inlining=copy+rename; inter-procedural; why single-block-leaf v0;
  the cascade) + 3-step figure. Exercises: cost model, multi-block inlining, bounded recursion, inline+re-opt
  fixpoint. **Next: `20-llvm-opt`** — hand optimized SIL to LLVM `-O2` (clang), measure vs swiftc -O; **M4**.
- **Concept 20 (`phase4-optimizer/20-llvm-opt`) is complete and verified — PHASE 4 DONE, Milestone M4
  reached.** Library `swiftml_llvmopt` (bin repointed). `-O` now = SIL passes + **clang -O2** (LLVM's
  optimizer + optimizing backend); `-Onone` = -O0. Skeleton `TODO(20)` = the run_clang oflag wiring (tiny
  on purpose — the concept's meat is the benchmark). **bench/**: 5 fold-resistant programs (fib 37,
  collatz 1M, primes 3M trial division, structs kernel 20M, enums state machine 30M) + bench.ml runner
  (compiles all 4 ways via Driver as a library, VERIFIES outputs agree, times warm best-of-3 via
  Unix.create_process; macOS gotcha: first exec stalls ~300ms in code-sign verification → warm-up run).
  **M4 MEASURED: swiftml -O = 129% of swiftc -O geomean (92–157% per bench)**, -O beats -Onone on all 5.
  HONESTY (in explainer §2): we skip Swift's overflow traps (plain add vs llvm.sadd.with.overflow), no
  ARC/exclusivity, subset flatters LLVM — claim stated as "same performance class on this subset with
  wrap arithmetic". **REAL BUG CAUGHT BY THE BENCHMARK: alloca-in-loop** — IRGen emitted alloca in the
  block of its alloc_stack, so a `let` in a hot loop grew the stack every iteration → segfault at ~250k
  iters (latent since Phase 2; no correctness test loops 3M times). Fix = hoist ALL allocas to the entry
  block (gen_allocas; what clang does; LLVM mem2reg requires it). Fixed in 20's irgen; alcotest pins it
  (allocas_outside_entry=0) — **backport to 09–19 pending** (review pass). Tests green RED→solution (cram
  -Onone-works/-O-RED + hot-loop-3M + composite; 3 alcotests). Deep explainer (two-level optimization,
  what -O2 does, honest-numbers section, the alloca story, timing methodology) + real-numbers bar chart
  (figs bake the measured run). Exercises: checked arithmetic (+re-measure), read the asm, LLVM-only -O,
  compile-time bench. **Phase 5 next** (strings/arrays/closures per PLAN.md).
- **FULL-COURSE REVIEW PASS done (post-M4).** Three structural fixes, all verified by a 15/15
  RED-on-skeleton/GREEN-on-solution matrix (05–20) + clean build:
  (1) **Per-concept `tests/lab.ml`** — cram tests used to invoke the PHASE binary (swiftml2/3/4),
  which links only the phase's LATEST concept, so per-concept cram RED/GREEN was broken (05–07/10–12
  vacuously green; 15–19 red only via 20's TODO). Now every concept 05–20 builds `./lab.exe` from its
  OWN library and its `.t` files call that. Convention is encoded in `_TEMPLATE-concept/` (now has
  dune.template, tests/dune.template + example.t.template, figs/make_figs.py, solution/README).
  (2) **alloca-hoist backported 09–19** (skeletons + solutions): all allocas emit at the top of the
  entry block via given `gen_allocas` (in 09 the Alloc_stack case is now a given no-op; its
  explainer §2 teaches the entry-block rule, §3/§8 updated; 20's bug story reframed as development
  history). (3) **Latent cram bugs fixed**: 08 sil.t whitespace drift re-promoted (dune promote with
  solution swapped); 13 optionals.t used unsupported `(re)` pattern + recorded a nondeterministic
  shell "Trace/BPT trap: <pid>" line — fixed with `sh -c './t; echo "exit=$?"' 2>/dev/null` (the
  echo inside prevents the inner sh exec'ing the binary). CRAM GOTCHAS (now in the template):
  `grep -c` exits 1 on count 0 (`|| true`); dune cram has NO `(re)`/`(glob)`; signal-killed binaries
  need the sh-wrapper. Plus doc/tooling accuracy: oracle.sh takes a binary arg (`make oracle F=… 
  B=swiftml4`); Makefile/CLAUDE/GUIDE bench example → 20-llvm-opt; `make test` documented as
  red-by-design on skeletons (no "fast subset"); flag list corrected (no `-Onone` flag; `--sil-opt`
  added); stale `swiftml/<module>.ml` paths fixed in 8 files; phase2 README "SSA" → memory-based;
  PLAN.md layout extended to phases 3–4; NEW phase3/phase4 READMEs; 00-setup exception noted;
  03-sema got its missing figure (env-walk) + exercise-2 reword; 09/20/03 PDFs re-rendered.
- **PHASE 5 STARTED (generics & protocols). Concept 21 (`phase5-generics/21-protocols-witness`) is
  complete and verified.** Library `swiftml_protocols`; binary **`swiftml5`** (phase5-generics/bin).
  Adds **protocols** through every stage: contracts (`Types.TProto`+`proto_layout` w/ req slots; ast
  proto decls + struct `sconforms`/`smethods`; sil `Init_existential`/`Apply_witness` + module
  `protos`/`wtables` + verifier checks tables reference real fns), lexer (`protocol` kw — NOTE the
  keyword table lives in token.ml not lexer.ml), parser (proto decls w/ method-req sigs, struct
  conformance clause + methods, `any P` normalized in parse_type_name), sema (PASS 0 protos + per-
  struct method sigs; conformance check w/ swiftc wording; methods: self + implicit field/method
  access, locals shadow properties, 'cannot assign to property: self is immutable'; existential
  coercion at let/args/return/assign; '==' on existentials rejected; 'any P has no member'), silgen
  (methods = plain fns `S.m` w/ self as arg 0; static Apply on concrete recv vs `Apply_witness` on
  existential; wtables per conformance in req-slot order), irgen (existential = `{[N x i64], ptr}`
  sized to LARGEST conformer — whole-module luxury vs swiftc's 3-word+boxing (concept 23); global
  const table per conformance + per-req THUNKS `w.P.S.i(ptr self,...)` that reload concrete self;
  per-site entry-hoisted buffers), opt (Apply_witness = call: side-effect+never CSE+blocks inlining;
  wtable fns kept alive in dead-fn removal). **Verified: 10/10 runtime parity vs swiftc incl -O**
  (heterogeneous dispatch, existential var reassign, zero-field conformers, mixed-size conformers,
  void reqs, protos+optionals) **+ 8/8 typecheck oracle** (conformance missing/wrong-sig, non-req
  member on 'any P', property write in method, non-conforming arg, == on existentials, inheritance
  from non-protocol). **TWO REAL SHIPPED BUGS found & fixed & backported & pinned:** (1) **Assign-wrap
  miscompile (13–20)**: Assign lowered with gen_expr not gen_expr_as-to-slot-type → `var x: Int? = 5;
  x = 7; print(x ?? 0)` printed 0 (raw store corrupted the tag); existential reassignment dispatched
  through garbage (surfaced as irgen assert under -O after mem2reg). Fixed in 13–21 silgen (incl 13's
  skeleton+solution), regression pinned in 13's cram. (2) **GVN type-blind value_key (18–20)**:
  `struct () $Zero` vs `struct () $One` merged (same key!) → wrong-table dispatch + ill-typed LLVM.
  Fix: value_key takes the RESULT TYPE; Struct/Enum keys include it. Backported 18 (skeleton sig+TODO+
  alcotest+cram regression), 19, 20, 21. Skeleton TODO(21) = sema struct_conforms + silgen wrap/
  dispatch/wtables; tests green RED→solution (cram SIL-shape+runs+-O+4 swiftc-worded rejections + 6
  alcotests incl. optimizer-keeps-tables). Deep explainer (existentials, tables, thunks, static-vs-
  dynamic, both bug stories) + witness-dispatch figure. v0: method reqs, non-mutating; mutating/
  property-reqs/defaults/notes = exercises. Next: `22-generics`.
- **Concept 22 (`phase5-generics/22-generics`) is complete and verified.** Library `swiftml_generics`
  (bin repointed). Adds **generic functions** `func pick<T: P>(_ a: T, _ b: T) -> T` + `where T: P`:
  contracts (`Types.TVar(name, constraint)`; ast func_decl.generics; sil `Open_existential` — the
  statically-checked unwrap at the call boundary), token/lexer (`where` kw), parser (`<T: P, …>` after
  the func name + where-clause merged into generics), sema (current_generics scoping → TVar; separate
  `gfuncs` table; **call-site INFERENCE**: bind T per arg position, conflict → swiftc's "conflicting
  arguments to generic parameter 'T' ('A' vs. 'B')", constraint → "global function 'f' requires that
  'A' conform to 'P'", substitute into ret; method calls on T via the constraint's reqs with bare-'T'
  error wording; '==' on T rejected; **v0 rejects unconstrained <T>** with a clear message — no
  metadata/boxing yet), silgen (the **unspecialized lowering**: ONE copy of the generic body with T
  ERASED to its constraint's existential — body method calls are already witness dispatch; call sites
  wrap T-args via Init_existential + OPEN the T-result via Open_existential when the inferred binding
  is concrete; generic-from-generic stays erased), irgen (open = extract payload buf → reload as the
  concrete type; per-site entry-hoisted buffer), opt (Open_existential pure + CSE-able with the type in
  the key). **Verified: 7/7 runtime parity vs swiftc incl -O** (T-result used concretely incl. field
  access, generic-calls-generic, where-clause, two conformers, generic in loop, generic+existential
  interop) **+ 4/4 typecheck oracle** (conflicting T, non-conforming arg, non-req member on T, accept).
  Skeleton TODO(22) = sema infer_generic_call + silgen call lowering (wrap/open); the erased lowering
  of the generic itself is given. Tests green RED→solution (cram one-@pick+open_existential SIL,
  runs+-O, 3 swiftc-worded diagnostics + 6 alcotests incl. unconstrained-rejected). Deep explainer
  (static identity vs any P; inference=mini-unifier vs CSGen; erasure model = swiftc's unspecialized
  path; why v0 needs constraints → metadata teaser for 23; "you're building the baseline 24 beats")
  + erasure figure (NOTE: matplotlib mathtext chokes on `$` in labels — descale SIL sigils in figs).
  Next: `23-existentials` (boxing, value witness tables, `as?` opening).
- **Concept 23 (`phase5-generics/23-existentials`) is complete and verified.** Library
  `swiftml_existentials` (bin repointed). Re-architects the existential to **swiftc's real container**:
  fixed `{ [3 x i64], ptr }` for EVERY protocol (21's whole-module max-sizing removed — the fixed
  layout is what separate compilation requires); conformers >3 words are **heap-BOXED** (malloc;
  buffer word 0 = box ptr; witness THUNKS unbox — type-specific knowledge lives in per-type code,
  dispatch sites stay uniform). Adds **dynamic casts**: `e as? T` (Optional diamond — the coalesce
  pattern) and `e as! T` (test-or-abort). Contracts: sil `Same_witness` (TYPE IDENTITY = WITNESS-TABLE
  IDENTITY — one ptr compare; swiftc uses type metadata) + term `Abort` (SIGABRT → **exit 134** like
  swiftc's cast failure, distinct from Trap/133; message text unmatchable: swiftc prints module-
  qualified names + addresses); ast `Cast`; `as` keyword; postfix parser (inline ident parse —
  parse_ident is defined AFTER the expr chain). Sema: cast typing (as?→T?, as!→T), **always-fails
  warning with swiftc's wording** for non-conforming targets, non-existential operand rejected.
  SILGen: cast to non-conformer = constant `false` (NO table exists to compare — referencing
  @wt.P.C for a non-conformance is a LINK ERROR, caught by the parity suite). **Driver fix: --typecheck
  now prints WARNINGS too** (was errors-only — caught when cram promotion DELETED the expected warning
  line; read your promoted diffs!). v0 honesty: POD payloads ⇒ box-sharing on copy is safe (CoW with no
  writes) and boxes LEAK (no ARC until Phase 6); value witness table taught as design, degenerate here.
  **Verified: 5/5 runtime parity vs swiftc incl -O** (5-word boxed conformer through funcs/reassign/
  casts/generics, as? discrimination, unrelated-cast nil) + as! failure **exit 134** ✓. Skeleton
  TODO(23a) = silgen cast lowerings, TODO(23b/c) = irgen inline-or-box write/read; container+thunks
  given. Tests green RED→solution (cram boxed+casts+warning verbatim+exit-134 + 5 alcotests). Deep
  explainer (fixed container & separate compilation, vwt taught-now-real-in-Phase-6, table identity,
  the warning-printing driver lesson) + container figure. NOTE freezing multi-line-header files:
  replace up to `let rec`-anchor, not the first `*)`. Next: `24-specialization` — **M5**.
- **Concept 24 (`phase5-generics/24-specialization`) is complete and verified — PHASE 5 DONE,
  Milestone M5 reached.** Library `swiftml_spec` (bin repointed). The two abstraction-erasing passes,
  both in `opt.ml`: **devirt_module** (peephole over SSA def-chains: `wrap_of` proves the concrete type
  — init_existential def, or already-TStruct inside a clone with the proto recovered from conformances,
  bailing on multi-conformance ambiguity; folds Apply_witness→Func_ref+direct Apply, Open→alias to the
  payload, Same_witness→Bool_lit which feeds simplify_cfg so provable as? deletes its fail branch) and
  **specialize_module** (worklist: for Apply of a `generic` fn — NEW `Sil.func.generic` flag, params/ret
  now mutable — where every TProto position proves the SAME sn and `retypable` holds (bails if the body
  builds its own existentials of that constraint), clone g→`g$sn` retyping ALL TProto→TStruct in
  val_ty/params/args/ret; call site passes raw payloads, retargets func_ref, retypes erased results so
  the caller's open folds; recursion specializes naturally — rep$A calls rep$A; unprovable sites stay on
  the erased original = swiftc's coexistence model). **Pipeline: inline → mem2reg → specialize → devirt
  → inline AGAIN → scalars** — the 2nd inline round is where abstraction dies (dbl$A ends as ONE
  struct_extract: GVN merges the two t.v() calls). **M5 MEASURED (bench/ + figs real numbers):
  genloop 101% / exloop 104% / maxgen 108% of swiftc -O, geomean 104%**; -Onone pays 1.8–4.5×.
  exloop honesty: existential params of a plain fn are unprovable for BOTH compilers — parity is
  pricing dispatch the same, not always erasing it. **8/8 runtime parity** (probes from 21/22/23,
  two-type clones, recursive generic, unprovable-stays-erased, generic+cast+boxed). Skeleton TODO(24a)=
  devirt folds, TODO(24b)=call-site specializer; clone machinery+worklist given. Tests green RED→
  solution first try (cram clone names+zero-witness greps+runs + 4 alcotests incl. non-generic-not-
  cloned). Deep explainer (proof→collapse, clone-per-type, the cascade, honest exloop reading) +
  real-numbers M5 figure. Exercises: speculative devirt, dead originals, clone caps, cross-clone GVN.
  Phase-5 README written. **Next per PLAN.md: Phase 6 — classes, vtables, ARC.**
- **PHASE 6 STARTED (classes & ARC). Concept 25 (`phase6-classes-arc/25-classes-vtables`) is complete
  and verified.** Library `swiftml_classes`; binary **`swiftml6`** (phase6-classes-arc/bin). Adds
  **classes** through every stage: contracts (`Types.TClass` + `class_layout` w/ cl_fields=FULL incl
  inherited (upcast-free prefix), cl_methods/cl_impls = the VTABLE in slot order; ast class_decl w/
  csuper/cinit(ONE, v0)/cmethods(override flags); sil `Alloc_ref`/`Ref_element_addr`/`Apply_class`
  (fused class_method+apply)/`Upcast` + module classes + sil_vtable printing + verifier), keywords
  (class/init/override/super; super.init parsed in primary — only spelling allowed), sema (recursive
  super-first layout build; **vtable rules: inherit slots, override REPLACES in place w/ both swiftc
  diagnostics, new appends**; DI: own fields assigned + super.init required — NOTE swiftc runs DI at
  SIL level so `-typecheck` won't show it, compare FULL compiles; init INHERITANCE when no own fields
  (constructor lookup walks the super chain — also in silgen); reference semantics: field writes legal
  through let bindings + in methods (no `mutating`); bare self-calls in class methods DISPATCH), silgen
  (constructor = Alloc_ref + init-owner call w/ Upcast; field access = Ref_element_addr+Load/Store;
  upcast at coercion points), irgen (`%obj.C = { ptr vtable, i64 refcount, fields }` — **refcount word
  reserved for 26**, set to 1; @vtbl.C globals; dispatch = 3 loads + call; Upcast = identity GEP — NOT
  an opnd alias: phis could read stale names), opt (Alloc_ref+Apply_class side-effecting; Ref_element_
  addr/Upcast pure+CSE-able; vtable impls+inits kept alive). **GOTCHA: silgen lower's ty_of_name needed
  the classes table declared BEFORE it (names registered in the early pass, layouts filled later)** —
  params silently fell back to TInt otherwise. **Verified: 8/8 runtime parity vs swiftc incl -O**
  (reference semantics/shared mutation, super.init chains, dynamic dispatch through superclass-typed
  vars AND through superclass methods calling overridden self-methods (the 7/407 probe), init
  inheritance, deep 3-level hierarchy, class+struct+protocol mix, ctor in loop) + DI vs full swiftc.
  Skeleton TODO(25a)=sema vtable build, (25b)=silgen dispatch, (25c)=irgen dispatch emission. Tests
  green RED→solution FIRST TRY (cram ref-semantics + sil_vtable listing + 7/407 + 4 exact-position
  diagnostics + 4 alcotests). Deep explainer (header design w/ reserved refcount, vtable invariant =
  inherited slot numbering, class-table-in-object vs existential-table-next-to-value, self-call
  dispatch, the leak cliffhanger → 26) + two-objects-two-vtables figure. v0: var props, one init,
  single inheritance; class-devirt/super.method/===+casts/final = exercises. Objects LEAK until 26.
  Next: `26-arc-runtime` (retain/release, deinit timing parity = the M6 oracle).
- **Concept 26 (`phase6-classes-arc/26-arc-runtime`) is complete and verified.** Library `swiftml_arc`
  (bin repointed). **ARC**: deinit TIMING/ORDER parity with swiftc -Onone is the oracle — **12/12
  lifetime scenarios byte-identical at -Onone AND -O** (scope exit reverse-decl-order, reassignment
  eval-new-then-release-old, shared-object once, statement-temps after the full statement, args
  GUARANTEED/borrowed, return = +1 transfer w/ retain-before-scope-releases, loop/break/continue
  releases, field replace, inheritance chains, cross-level fields). Contracts: sil `Retain`/`Release`
  (side-effecting — NO pass may drop/reorder; value_key None); `deinit` kw + class_decl.cdeinit.
  SILGen = the ARC INSERTION: builder gets `owned` (fresh +1 temps: Alloc_ref ctor results + class-
  typed call results via mark_owned), `take_ownership` (consume an owned temp / Retain a borrow) at
  ALL store sites (Let/Assign/Set_member/bare-field/return), `stmt_temps` released per statement,
  scope STACK released newest-first on fallthrough + release_down_to for return/break/continue (loops
  now carry their entry scope-depth), in_init skips release-old on first field stores. **main's
  top-level vars are GLOBALS: never released** (swiftc runs no deinit at exit — first run printed one
  extra). **DEALLOCATION IS TWO CHAINS (probe-caught divergence!): ALL deinit bodies derived→base
  FIRST (vtable slot 0, `C.deinit`), THEN all field releases base→derived (slot 1, `C.destroy`), then
  ONE free** — the obvious per-level order is plausible and WRONG (swiftc: 2000,1003,7 not 2000,7,
  1003); methods shift to slot+2. IRGen: rt.retain/rt.release defined in the preamble (NOTE: OCaml
  has no \32 escape — build runtime IR as a String.concat list, not inside a long literal);
  release@0 = vt[0], vt[1], free. opt: destructors+destroyers kept alive (reachable only via vtable —
  the wtable blind spot again). v0 guards: class refs inside structs/enums/optionals REJECTED (bitwise
  copies corrupt counts); cycles leak like real Swift (weak = exercise). Skeleton TODO(26a)=take_
  ownership, (26b)=destroy chain, (26c)=rt.release. Tests green RED→solution (cram all orderings + -O
  + guard diagnostic; 5 alcotests incl. per-function retain/release counts + both chains' structure).
  Deep explainer (ownership model, cleanup stack, the two-chain discovery as oracle-discipline lesson,
  honest boundaries, ARCOptimization.md pointer) + lifetime figure. Next: `27-ownership` (ownership
  SSA, copy/destroy_value, verifier) then `28-arc-optimization` (M6's perf half).
- **Concept 27 (`phase6-classes-arc/27-ownership`) is complete and verified.** Library
  `swiftml_ownership` (bin repointed). **Ownership SSA**: 26's raw Retain/Release recast as
  STRUCTURED ops — `Copy_value` (borrow→new +1 owner; lowers to rt.retain + identity GEP),
  `Destroy_value` (consume), **`Load_take`** (`load [take]`: a slot's +1 moves out FREE — scope
  exits/overwrites/destructor fields are now take+destroy, not borrow+release-a-borrow). Every
  class-typed value classified OWNED (alloc_ref/copy/take/call results; consumed EXACTLY once by
  destroy/store/return) or GUARANTEED (params incl self, plain loads; NEVER consumed, no traffic).
  **THE OWNERSHIP VERIFIER** (`Sil.verify_ownership`, run by the driver on EVERY compile): R1
  exactly-once (0=leak, n=double-consume), R2 never-consume-a-borrow, R3 no-use-after-consume
  (block-local v0). **The verifier improved its own compiler on first run**: every class param was
  spilled to a slot at entry (Phase-2 uniformity) and the entry store CONSUMED A BORROW (R2 ×3 per
  class) — fix = the real OSSA design: class-typed params (incl self) stay PURE SSA values (new
  builder `borrows` map; self_ref helper; no slot/store/loads — also fewer instructions). silgen:
  take_ownership now RETURNS the value to store (the copy, not the borrow). opt: Load_take joins
  Load in mem2reg (value_uses/gen-kill/rename); Copy/Destroy side-effecting, never CSE'd.
  **Verified: 10/10 lifetime parity UNCHANGED at -Onone AND -O** (the recast is behavior-preserving)
  + verifier silent on all generated SIL. Skeleton TODO(27) = the verifier core (in sil.ml — the
  contract file hosts both verifiers). Tests green RED→solution (cram structured-ops counts +
  no-spill init signature + lifetime runs; 6 alcotests: clean generated SIL, copy-then-destroy
  legal, and FOUR HAND-BUILT bad-SIL violations w/ exact messages — source can't express them, the
  IR can; promote caught a missing reassign-deinit `4` in my hand-golden). Deep explainer (the
  lattice, load [take]'s elegance, the verifier-caught-the-spill story, why-bother→28, Ownership.md
  pointers) + lattice figure. v0: function-wide R1 (path-sensitive = exercise), block-local R3;
  exclusivity needs inout = exercise. Next: `28-arc-optimization` — **M6**.
- **Concept 28 (`phase6-classes-arc/28-arc-optimization`) is complete and verified — PHASE 6 DONE,
  Milestone M6 reached.** Library `swiftml_arcopt` (bin repointed). **copy_propagation** (in
  default_pipeline after mem2reg; runs again post-inline): deletes a `copy_value`/`destroy_value`
  pair when (1) the copy's ONLY consuming use is a same-block destroy with all uses inside the
  bracket, (2) the SOURCE outlives it (param, or owned value consumed later same-block — a
  LOAD-sourced copy fails both, CORRECTLY: `var a=T(1); let c=a; a=T(2)` — the copy is what keeps
  T(1) alive; probe pins it), (3) **ONE rewrite per sweep** (stale-index cascade on chained copies
  corrupted IR → IRGen Not_found; fixpoint recomputes). Plus **WMO class devirtualization** in
  devirt_module: receiver's static class has NO subclasses in the module → dispatch has one answer →
  direct call → inliner eats it (override hierarchies untouched, probed). **M6 MEASURED**:
  borrowloop (30M copy/destroy pairs deleted) **0.009s vs swiftc -O 0.012s = 143%**; handoff (3
  chained copies ×20M) 110%; **geomean 126%**; 6.9× over our -Onone. **12/12 deinit-parity at -O
  intact** incl. the adversarial keep-case. COMPOSITION INSIGHT (test-pinned): the pass ALONE keeps
  a return-consumed copy (ownership transfer), but the full pipeline may erase it AFTER inlining
  exposes both ends — sound alone and composed (test uses run_pipeline [mem2reg; cp] not optimize).
  NOTE: ownership verifier guards RAW SIL only (post-mem2reg ownership threads through phis —
  like swiftc lowering OSSA before late passes); soundness gate for the optimizer = the behavioral
  suite. Skeleton TODO(28) = the rewrite (use-map scaffolding + fixpoint + WMO devirt given). Tests
  green RED→solution (cram removal/cascade/keep-case/devirt-vs-override + 5 alcotests incl.
  conservation destroys=copies+allocs). Deep explainer (bracket-in-lifetime, the 3 checks w/
  counterexamples, the stale-index lesson, WMO devirt, honest -Onone comparison) + real-numbers M6
  figure + bench/. Phase-6 README written. **Phases 0–6 complete, M0–M6 all measured/verified.
  Next per PLAN.md: Phase 7 — closures, errors, stdlib (29-closures first).**
- **PHASE 7 STARTED (closures/errors/stdlib). Concept 29 (`phase7-closures-stdlib/29-closures`) is
  complete and verified.** Library `swiftml_closures`; binary **`swiftml7`**. **Function types are
  first-class**: `Types.TFunc(ps, ret)`; parser encodes written fn types canonically `"(Int,Bool)->Int"`
  (resolvers split via `Types.split_fn_written` — the string-based written-type pipeline survives);
  closure literals `{ (x: Int) -> Int in expr }` (explicit param types, SINGLE-EXPR bodies v0; `in` kw
  reused). **The ABI: thick pair `{code ptr, ctx ptr}`** (`%thickfn`); contexts = refcounted heap
  objects (no-op-destructor vtable) holding BY-VALUE captures (PODs only v0 — managed captures need
  ctx destroy entries = the vwt story again, exercise); named fns as values via per-target THUNKS +
  null ctx (rt.retain/release gained NULL-GUARDS so thin traffic is free); `@escaping` parsed-and-
  ACCEPTED (we don't track escaping — permissive divergence, checker = exercise; needed `@`/At token).
  SIL: `Closure(fn, caps)` / `Thin_to_thick` / `Apply_value` / `Capture_get` + modul.closures layouts.
  SILGen: closures LIFT during lowering (gen_expr ↔ lower_func now MUTUALLY RECURSIVE — merged the
  three rec chains; `~lifted` ref threads through; prologue binds Capture_gets into borrows; ret
  patched from the lifted body when unannotated); fv_expr FV analysis; indirect calls for fn-typed
  locals; **TFunc joins TClass as a MANAGED type** (one is_class_ty change powers all ARC paths).
  **The ownership verifier caught TWO more pre-runtime bugs**: Closure/Thin_to_thick results not
  mark_owned'd (leak + spurious copy) and TFunc params still spilled (store-consumes-borrow — the
  same flaw it caught for classes in 27). sema: closure typing self-describing; capture FLOOR stack
  (env-length at closure entry) → managed-capture rejection + assign-to-capture check (dead code in
  v0: single-expr bodies can't parse assignments — a promote exposed my unreachable test; cleaned).
  ast: `param` hoisted above `expr` (Closure references it). **Verified: 6/6 parity vs swiftc incl -O**
  (literals/HOF/independent adder contexts/named-fn values/struct captures/reassigned fn vars/nested
  closures/closures-in-loops/ARC interplay: Box dies at scope exit since the VALUE was captured) +
  ownership-clean SIL. Skeleton TODO(29a)=the lifting, (29b)=irgen indirect call. Tests green RED→
  solution (cram SIL shapes+behavior+rejection verbatim + 4 alcotests incl. layout + ownership-clean).
  Deep explainer (Landin split, capture-list semantics, thunk uniformity, the verifier-strikes-twice
  story) + ABI figure. Exercises: closure devirt, boxes, managed captures, @escaping, multi-stmt.
  Next: `30-error-handling` (throws/try/do-catch — the error-return ABI).
- **Concept 30 (`phase7-closures-stdlib/30-error-handling`) is complete and verified.** Library
  `swiftml_errors` (binary swiftml7). `throws`/`try`/`try?`/`try!`/`do`-`catch`/`defer` as **PURE
  DESUGARING** — errors travel in a single Int register `@swiftml.error` (= swiftc's reserved x21),
  so EVERYTHING lowers to branches + two runtime intrinsics (`rt.error_get`/`rt.error_set`); **zero
  new SIL instructions**. token/lexer (NOTE keyword table is in token.ml's keyword_or_ident, NOT
  lexer.ml — my first edit silently no-op'd; `@`/At + throws/throw/try/do/catch/defer), ast
  (`Try`/`Throw`/`Do`/`Defer`, func.throws, enum.is_error, catch_clause), parser (try prefix; throw/
  do/defer stmts; `enum E: Error`; throws between params and `->`; CATCH newline-tolerant lookahead
  with p.pos save/restore — `}` and `catch` may be same-line OR next-line, and we must not eat the
  statement separator), sema (error-enum ordinals 1.. ; throwing-funcs set; `try?`/`try!` HANDLE
  locally so they count as a handling context; throw/do count as returning in missing-return; two
  swiftc diagnostics exact), silgen (the desugaring: throw=set+branch-to-handler; throwing-Apply→
  emit_error_check; do=ordinal dispatch w/ clear-on-match; try?=Optional diamond; try!=Trap(133);
  defer=LIFO via a parallel stack on the concept-26 scope cleanup, fires on fall-through/return/
  break/continue/throw-propagate; gen_throw_propagate runs defers+ARC+return default_value),
  irgen (the @swiftml.error global + rt.error_get/set in the runtime preamble). **Verified: 8/8
  runtime parity incl -O** (do-catch by case, nested 3-deep propagation, defer LIFO + on-throw,
  try?/try!, multi-catch, defer-in-loop, classes+errors ARC interplay) + try! exit **133** + **4/4
  diagnostics**. Skeleton TODO(30a)=post-call error check, (30b)=catch dispatch; throw/try?/try!/
  defer/rt given. Tests green RED→solution (cram do-catch+defer+133+2 diagnostics + 6 alcotests).
  Deep explainer (errors=second return path, propagation by early-return not unwinding, do=switch,
  try-flavours=handler swaps, defer=concept-26 cleanup, ErrorHandlingRationale pointer) + desugar
  figure. v0: payload-free error enums; throwing funcs return scalar/optional/void/enum; closures
  don't throw. STALE-BUILD GOTCHA: `dune exec --no-build` after a token change used the old binary —
  always `dune build` (no --no-build) after lexer/token edits. Next: `14-memory-layout` (backfill),
  then 31/32 (→ M7).
- **Concept 14 (`phase3-value-types/14-memory-layout`) is complete and verified — BACKFILL of the
  deferred Phase-3 chapter.** Library `swiftml_layout` (carried from 13-optionals; phase3 bin
  swiftml3 repointed to it — 14 is a leaf, doesn't feed the forward chain). New `layout.ml`:
  size/stride/alignment + struct field OFFSETS via the natural-alignment padding walk (`info_of`
  dispatch + scalar/enum/optional sizes + `stride` given; learner holes `struct_info` TODO(14a)
  = the padding accumulation, `field_offsets` TODO(14b)). New `--emit-layout` driver mode + bin
  flag. **Verified: byte-exact parity vs swiftc `MemoryLayout<T>`** on structs of scalars: P{Int,
  Int}=16/16/8, Mixed{Bool,Int}=16 (Bool padded), Mixed2{Int,Bool}=**size 9**/stride 16, Three=16
  w/ offsets 0,1,8, nested Outer=24 — all match .size/.stride/.alignment/.offset(of:). HONEST
  DIVERGENCE (explainer's how-swiftc-does-it): enums/optionals use swiftml's naive {i64 tag,
  payload}; swiftc packs the tag into the payload's SPARE BITS (Optional<class> = pointer-sized,
  nil=null; Int?=9 not 16) — TypeLayout.rst spare-bit machinery, an optimization on top of the
  universal padding rule. Skeleton TODO(14a/b); tests green RED→solution (cram 4-struct+offsets+
  nested vs MemoryLayout numbers + 4 alcotests). Deep explainer (size vs stride vs align, why field
  ORDER changes size, spare-bit packing) + padding figure. Phase-3 backfill complete. Next: 31/32
  (→ M7).
- **Concept 31 (`phase7-closures-stdlib/31-stdlib-array-string`) is complete and verified.** Library
  `swiftml_arrays` (bin `swiftml7` repointed). Adds **`Array<Int>`** and **`String`** on the HEAP,
  with **value semantics via copy-on-write** — the first stdlib types, lowered to runtime
  INTRINSICS (`rt.array_*`/`rt.str_*`, ordinary Applies of Func_refs), **zero new SIL** (same trick
  as 30). An array = a ptr to a refcounted buffer `{i64 refcount, count, capacity, ptr data}` (data
  a separate malloc, doubling grow min 4); a String = a libc C-string. Through every stage: types
  `TArray of ty` + `split_array_written` ("[T]" canonical); token `LBracket`/`RBracket` (were
  MISSING — added to token.ml + lexer.ml); ast `Array_lit`/`Subscript`/`Set_subscript`/`For_in`;
  parser (`[a,b]` atom, `a[i]` postfix, `for x in arr` non-range, `a[i]=e`, `[T]` type); sema (TArray
  typing, `.count`/`.isEmpty`, `append`, subscript r/w, array-lit element unify, for-in element bind,
  String `+`→TString + `.count`); silgen + irgen (the `rt.*` runtime, given). **CoW = retain on
  share (`var b=a`→`rt.array_retain`) + make_unique before a mutation (copies iff refcount>1).**
  Skeleton `TODO(31a/b)` = the **copy-on-write dance** for the two mutators (`append`, `a[i]=e`):
  load slot → `rt.array_make_unique` → STORE pointer BACK → push/set (the store-back is the classic
  CoW bug). **Array+String programs RUN and match swiftc byte-for-byte** (-Onone & -O): literal/
  count/subscript r/w/append/for-in/isEmpty, String concat+count; **`var b=a; b.append/b[0]=` leaves
  `a` unchanged** (value semantics); arrays by-value to funcs. **OOB subscript traps EXACTLY like
  swiftc**: "Fatal error: Index out of range" to stderr + **exit 133** (llvm.trap). **v0 scope = `[Int]`
  only** (homogeneous i64 buffer); `[String]`/`[Bool]` REJECTED up front with a clean sema diagnostic
  (element-generic buffers via zext/ptrcast = exercise 1, unlocks concept 32). String is byte-indexed
  ASCII (grapheme `.count` = documented divergence). Tests green RED→solution (cram builds+runs+CoW+
  traps + 7 alcotests incl. retain-once/make_unique-per-mutation counts). Deep explainer (buffer
  layout, CoW = share-then-copy-on-write, swiftc's `isKnownUniquelyReferenced`, the store-back bug) +
  CoW figure. **CAUGHT+FIXED A CARRY-FORWARD GAP**: the silgen/irgen carried from 30 still had concept-29's
  `TODO(29a-silgen)` closure-lift + `TODO(29b-irgen)` thick-call as `failwith` HOLES (30's solution
  never filled them — its corpus has no closures, so it passed anyway). Filled both from 29's solution
  so closures work in 31 and the chain is clean for **concept 32 (map/filter/reduce needs closures)**.
- **Concept 32 (`phase7-closures-stdlib/32-stdlib-collections`) is complete and verified — Milestone
  M7, Phase 7 DONE.** Library `swiftml_collections` (bin `swiftml7` repointed). Adds the **higher-order
  trio `map`/`filter`/`reduce`** over `Array<Int>` — **the payoff that unites concept-29 closures with
  concept-31 containers**. Each is a **counted loop over the buffer calling the closure per element via
  `Apply_value`** — **zero new SIL, zero new runtime** (reuses rt.array_get/push/count + the thick-fn
  ABI). PURE SILGEN: no parser/token/ast changes (the parser already makes `a.map({...})` a
  Method_call; reduce = `a.reduce(0, {...})` 2-arg). sema = typing only (given: map closure `(E)->R`→
  `[R]`, filter `(E)->Bool`→`[E]`, reduce `(init:R)` + `(R,E)->R`→`R`, wrong-shape rejected). silgen
  learner hole `TODO(32)` = `gen_array_hof`'s **three loop bodies** (the `loop ~body_fill` counted-walk
  scaffold + `rt_call` helper given): map builds+pushes a `[R]` result, filter branches on the Bool
  predicate (keep/skip) pushing kept elts into `[E]`, reduce folds into an `Alloc_stack "$acc"` slot.
  **map/filter/reduce RUN and match swiftc byte-for-byte** (-Onone & -O): chained `map().reduce()`,
  filter+for-in, **closures capturing outer vars** (`a.map { x*factor }`), sum-of-squares reduce, empty
  arrays, filter-keeps-nothing. map/filter only READ the source (no CoW); results born refcount 1.
  **v0 scope = `[Int]`** (concept 31's restriction) + explicitly-typed closures (29); **paren-form
  closure args** (`a.map({...})`, both compilers accept) — **trailing-closure `{ }` + `$0` shorthand =
  exercise** (parser-only, lowering identical); Dictionary/Set/Range + Sequence/Collection PROTOCOLS =
  v1 (need hashing+new containers, exercises). Tests green RED→solution (cram chained-trio+empty+SIL-
  shape (apply_value-per-closure, reduce-no-result-array) + 6 alcotests). Deep explainer (one-shape-
  three-outcomes, swiftc's `Sequence.map/filter/reduce` ARE for-loops, apply_value carries captures,
  read-not-mutate) + HOF figure. **M7 SEALED**: a combined program (throws/try?/do-catch + arrays+CoW
  append + closures + full trio) matches swiftc byte-for-byte at -Onone AND -O. **Phase 7 complete;
  next = Phase 8 (the from-scratch ARM64 backend), starting 33-arm64-isel → M8.**
- **PHASE 8 STARTED (the from-scratch ARM64 backend, no LLVM). Concept 33
  (`phase8-arm64-backend/33-arm64-isel`) is complete and verified.** Library `swiftml_isel`; binary
  **`swiftml8`** (phase8-arm64-backend/bin). **Backend B**: SIL → **ARM64 assembly** (Apple/macOS
  arm64) → `clang`(as/ld) → native exe, alongside the LLVM spine (Backend A). DECISION (stated, not
  asked): emit **asm TEXT** (assembled by `as`), real machine-code encoding = ladder top (deferred);
  lower the **raw -Onone (memory-based) SIL** (no block args — SSA φ-lowering arrives with regalloc).
  New **`arm64.ml`** (contract): the ARM64 instr IR (mov/movz/movk/add/sub/mul/sdiv/msub/cmp/cset/
  csel/ldr/str/stp/ldp/adrp/b/b.cond/bl/brk/ret) + `reg = X|SP|XZR|Virt` (Virt reserved for 34) +
  the `as`-assemblable printer (Apple syntax, `_`-prefixed syms, adrp/add @PAGE/@PAGEOFF, __cstring
  section). New **`isel.ml`**: SIL→ARM64 as a **NAIVE STACK MACHINE** — every SIL value gets a frame
  slot (`[sp,#16+8*v]`), each op loads operands to scratch x9/x10/x11, computes, stores back; sp
  fixed for the body (so call-arg shuffling is easy), printf's variadic at `[sp,#0]` (**Apple
  variadic-on-stack ABI** — Linux would use x1), mod=sdiv+msub, comparisons=cmp+cset, calls=args in
  x0..x7 + `bl _name`, params spilled on entry. driver `--emit-asm` + `build --native`. Skeleton
  `TODO(33a)` = `sel_instr` (per-op templates), `TODO(33b)` = `sel_term` (branches+return); the
  frame/prologue/materialize/slot/cstring scaffolding + arm64.ml given. **Native ARM64 exe RUNS and
  matches swiftc**: arithmetic, neg, if/else, while, for, bool (true/false print), funcs, recursion
  (fib 25), nested loops, comparison chains, AND collatz/primes/mutual-recursion/gcd/big-constants —
  all byte-for-byte + **Backend B agrees with Backend A** (the LLVM path). Tests green RED→solution
  (cram builds+runs native + asm-shape greps + A/B agreement; 8 alcotests on instr kinds). Deep
  explainer (stack machine, the frame, AAPCS64 calls, the Apple variadic gotcha, sdiv+msub, why
  lower -Onone, select→allocate→schedule→encode) + stack-machine figure. **v0 scope = Int/Bool +
  arithmetic/comparison/control-flow/functions/print**; structs/enums/classes/ARC/arrays/closures =
  out of v0 (an unsupported op → visible `; UNSUPPORTED` comment, no miscompile), grow in later
  concepts. CRAM GOTCHA: process substitution `<(...)` is unsupported by the cram shell — compare via
  temp files. Next: **34-register-allocation** (the ladder: stack→linscan→graphcolor; vregs + the
  optimized SSA path; the Virt register comes alive) → makes the stack machine fast.
- **Concept 34 (`phase8-arm64-backend/34-register-allocation`) is complete and verified — the
  flagship Phase-8 concept, a runnable REGISTER-ALLOCATION LADDER.** Library `swiftml_regalloc`
  (bin `swiftml8` repointed). isel REWRITTEN to emit over **virtual registers** (each SIL value →
  `Virt v`; no prologue/epilogue — finalized after allocation; params moved from x0..x7; mod-temp +
  print-temps are fresh vregs). New **`regalloc.ml`** maps vregs → physical with **3 rungs**
  (`--regalloc=stack|linscan|graphcolor`, default graphcolor): **v0 stack** (spill all ≈ concept
  33), **v1 linear-scan** (Poletto-Sarkar over live intervals; spill the interval ending latest),
  **v2 graph-colour** (Chaitin-Briggs: interference graph from interval overlap → simplify/spill/
  select). KEY DESIGN (makes it short+correct): **pool = callee-saved x19..x27** so any allocated
  value survives a `bl` for FREE (no call-clobber modelling); x9..x14 = spill scratch; a "spill" =
  "live in the vreg's own slot [sp,#16+8v]" (every vreg has a home, no spill-slot alloc). Given:
  `liveness` (backward dataflow to fixpoint over a CFG built from branch targets), `intervals`,
  `map_regs`/`rewrite` (vreg→physical, loads spilled operands into scratch, reports used callee-
  saved), `finalize` (prologue sub sp + save fp/lr + save USED callee-saved; epilogue before every
  ret), v0 `stack_alloc`. Skeleton `TODO(34a)` = linscan core, `TODO(34b)` = graphcolor core.
  **All 3 rungs produce native binaries matching swiftc** (fib, loops, collatz, primes, gcd,
  nested) + **Backend B agrees with Backend A**. **LADDER MEASURED (bench/ real numbers): stack→
  graphcolor 4.3x/2.3x/2.4x, geomean 2.9x; reaches ~45% of our LLVM -O path.** memory traffic on
  fib+loop: stack 95 ldr/str + 0 callee-saved → graphcolor 41 + uses x19-x23. linscan≈graphcolor on
  LOW pressure (coincide; diverge only when live values > 9-reg pool). HONEST GAP to LLVM = variables
  stay in alloc_stack memory (we lower raw -Onone SIL; only TEMPORARIES get registers) — promoting
  via mem2reg+phi-elim (concept 16!) is exercise 1, the documented next step. Tests green RED→solution
  (cram 3-rungs-match-swiftc + ldr/str counts + callee-saved use + A/B agreement; 6 alcotests incl.
  the SOUNDNESS check: no two overlapping intervals share a register, checked vs the interference
  relation directly). Deep explainer + ladder figure (real bench bars). Next: **35-mc-abi** (full
  AAPCS64 frames/calls), 36-peephole-sched (would kill the redundant str/ldr pairs), 37-debug-info
  → **M8-core**.
- **Concept 35 (`phase8-arm64-backend/35-mc-abi`) is complete and verified.** Library `swiftml_abi`
  (bin `swiftml8` repointed). Makes Backend B **AAPCS64-conformant**: arguments **beyond 8 go on the
  STACK** (concepts 33/34 only handled ≤8 args — a real correctness bug: a 10-arg call gave 47 not
  55). isel (the learner file): an **outgoing stack-arg area** at the frame bottom sized to the
  widest call (`outgoing = max 2 max_stack_args`; value slots shifted above it); call site stores
  arg k≥8 at `[sp,#8*(k-8)]` (TODO(35a)); callee reads param k≥8 at `[x29,#16+8*(k-8)]` via x29 = the
  incoming sp (TODO(35b); +16 skips saved fp/lr). Also a **LARGE-FRAME-SAFE prologue** (given, in
  regalloc.finalize) — the OLD single-`sub` + `stp [sp,#frame-16]` overflowed stp's ±512 imm on a
  12-arg function; new shape: `sub sp,#16; stp x29,x30,[sp,#0]; mov x29,sp; sub sp,#locals` (push
  frame record first, offset-0 stp always in range, x29 = stable frame handle). **10-arg (55) +
  12-arg (78 38) functions RUN and match swiftc across all 3 regalloc rungs** + ≤8-arg corpus
  unchanged (fib/loops/collatz). Skeleton carry-forward: ≤8 path GIVEN (works), only the >8 stack
  path is the hole (failwith). Tests green RED→solution (cram 10/12-arg-match-swiftc + outgoing-
  store/x29-load greps + offset-0-stp + ≤8-unchanged; 4 alcotests incl. small-calls-register-only +
  frame-safe-prologue). Deep explainer (ABI = the call contract; register-then-stack classification;
  caller [sp,#8j] = callee [x29,#16+8j] same byte; why x29 not sp; the frame-record-first fix) + ABI
  figure. v0 scope = Int args (Double→d0-d7 + aggregates-by-ref + stack alignment = exercises); "real
  machine-code encoding" (Mach-O object, no `as`) stays concept-33 exercise 5. Next: **36-peephole-
  sched** (peephole: kill redundant str/ldr + mov; instruction scheduling over a dep DAG), 37-debug-
  info → **M8-core**.
- **Concept 36 (`phase8-arm64-backend/36-peephole-sched`) is complete and verified.** Library
  `swiftml_peephole` (bin `swiftml8` repointed). Adds a **PEEPHOLE pass** (`peephole.ml`) over the
  final post-regalloc ARM64 stream + a (given identity) scheduler. The learner hole `TODO(36)` =
  `rewrite_block`: **within-block local redundant-load elimination** — keep a `held : slot→register`
  table; a `Ldr` of a slot already in a register becomes a `Mov` (or is DROPPED if the same reg
  holds it); `Mov x,x` dropped; **invalidate** on any register write (`snd reads_writes`), `Hashtbl.
  reset` on `Bl`, and the table resets per basic block (no cross-block forwarding). Given: block
  splitting, the fixpoint driver, `kill_reg`. Wired into the backend after regalloc (default ON;
  `--no-peephole` to compare). **Verified: peephole'd code matches swiftc** (fib/collatz/loops/
  primes/gcd/manyarg) AND the --no-peephole backend; **straight-line loads 18→11** (redundant ldr →
  mov the CPU renames ~free). Tests green RED→solution (cram on/off match + load-count drop +
  store/reload-same-reg removed; 6 alcotests: 3 rewrite shapes + 2 SOUNDNESS guards (clobber keeps
  the load; no forwarding across a label) + load-reduction). **HONEST PERF (the lesson, in the
  explainer)**: peephole removes LOCAL (within-block) redundancy only → small runtime win, because
  the DOMINANT cost is CROSS-block (every block reloads alloc_stack variables) which needs mem2reg/
  SSA promotion (concept 34 exercise), NOT a peephole; and instruction SCHEDULING is ~free on Apple's
  out-of-order cores (scheduler kept = identity, honestly noted). Match the pass to the redundancy.
  Deep explainer (the slot→reg table, invalidation = the whole game, local-vs-structural, OoO
  scheduling) + peephole figure. Exercises: strength reduction, immediate folding, dead-store elim,
  branch peepholes, a real DAG list scheduler. Next: **37-debug-info** (thread source locations →
  DWARF-lite `.loc` line table → lldb stepping) → **M8-core**.
- **Concept 37 (`phase8-arm64-backend/37-debug-info`) is complete and verified — Milestone M8-CORE
  reached.** Library `swiftml_debuginfo` (bin `swiftml8` repointed). Makes a swiftml-built native
  binary **DEBUGGABLE**: thread source LINE NUMBERS end-to-end → a real **DWARF line table** lldb can
  step. Given plumbing: `Ast.stmt_line` (stmt→line); SILGen builder gets `lines:(value,int)Hashtbl` +
  `cur_line` (set per stmt in gen_stmt), and `emit` STAMPS `lines[v]=cur_line` (one place, every
  value); `Sil.func` gains a `lines` field (also carried by opt.ml's specialize clone); `Arm64`
  gains `Loc of int` (`.loc 1 N 0`) + `modul.source` (`.file 1 "src"`); driver `-g` build **keeps the
  `.o`** (macOS = DWARF-in-.o + debug-map-in-exe; `clang -g file.s -o exe` deletes the temp .o and
  loses DWARF — so assemble to `<out>.o` then link). Learner hole `TODO(37)` = `emit_loc` in isel:
  emit `Arm64.Loc line` when `f.Sil.lines[vv]` differs from `!last_line` (consecutive same-line
  instrs share one .loc). **VERIFIED: real DWARF line table** — `dwarfdump --debug-line` on the .o
  maps addresses→source lines EXACTLY (0x24→L2, 0x30→L3, 0x70→L5, ...; `2 3 5 6 7 8`) + programs run
  and match swiftc + lldb breakpoint-by-line/step works (manual, in explainer — lldb too flaky to
  automate, so the AUTOMATED check is the dwarfdump line table). Tests green RED→solution (cram
  .file/.loc-per-line + native-runs + dwarfdump line table; 4 alcotests: .loc-per-line, dedup-per-
  stmt, SILGen-stamps, .file+.loc-in-asm). Deep explainer (line table = addr↔line; the threading
  chain; why .loc not hand-encoded DWARF; the macOS debug-map wrinkle; lldb session) + threading
  figure. v0 = LINE TABLE only (breakpoints+stepping); variable locations/.debug_info DIEs (so
  `print x` works)/columns/.dSYM/inlined-frames = exercises; hand-encoding the DWARF line program =
  exercise 1. **M8-CORE COMPLETE**: the from-scratch ARM64 backend — isel(33) + regalloc ladder(34,
  ~2.9× over naive) + AAPCS64(35) + peephole(36) + debug-info(37) — compiles the scalar/control-flow/
  functions corpus correctly (differential vs LLVM path AND swiftc), fast, AND debuggable; TWO
  backends, ONE front end. Next: the project tail **38-async-await, 39-actors, 40-macros** → DONE.
- **PROJECT TAIL STARTED (language completeness, on the FULL-LANGUAGE LLVM path — these carry from
  phase7/32, NOT the scalar ARM64 backend). Concept 38 (`phase8-arm64-backend/38-async-await`) is
  complete and verified.** Library `swiftml_async`; binary **`swiftml9`** (phase8/bin-lang, phase7-
  style CLI, no --native). Adds **`async`/`await`/`Task {}`/`Task.yield()`** lowered onto a
  **COOPERATIVE EXECUTOR** with real **stackful coroutines** — **zero new SIL** (runtime calls, same
  trick as errors/arrays). token (async/await kw), ast (func_decl.is_async; `Await` expr; `Spawn`
  stmt), parser (async between params/arrow like throws; `await` prefix; `Task {…}`→Spawn;
  `Task.yield()` stays Method_call), sema (await transparent; `Method_call(Var"Task","yield",[])`→
  TVoid placed BEFORE the generic Method_call; Spawn checks body), silgen (await→gen e; yield→
  `rt_async_yield`; **Spawn→lift body as a void coroutine fn `main$taskN` + `Closure(name,[])` +
  `rt_async_spawn` + Destroy_value** = the learner hole TODO(38); main epilogue `rt_async_run` via
  lower_func's ~epilogue), irgen (declare rt_async_yield/run + rt_async_spawn(%thickfn) AFTER the
  type defs since %thickfn is forward), driver (**the C runtime EMBEDDED as a string, compiled+linked
  every build** via `clang -Wno-deprecated-declarations file.ll rt.c`: ucontext stackful coroutines +
  FIFO ready queue; closure {code,ctx} passed by value = `swiftml_closure` struct). **ucontext WORKS
  on macOS arm64 with `_XOPEN_SOURCE=700`** (tested). **VERIFIED: sequential async MATCHES swiftc
  byte-for-byte** (36/1296; `await worker(1);await worker(2)`→11,12,21,22) + **3 spawned tasks
  interleave round-robin** `0 11 21 31 12 22 32 13 23 33` (our cooperative executor). HONEST: we model
  a SERIAL deterministic FIFO executor; Swift's default executor is concurrent/nondeterministic — so
  match swiftc on DETERMINISTIC sequential async, verify interleaving vs our documented semantics.
  swiftc uses STACKLESS coroutines (CPS state machines); we use STACKFUL (stack per task) for
  simplicity — same semantics. v0 tasks CAPTURE-FREE (managed captures = exercise). Tests green RED→
  solution (cram seq-matches-swiftc + round-robin + rt_async_* SIL; 5 alcotests). Deep explainer
  (stackful vs stackless, the executor, runtime-call lowering, the honest swiftc difference) + figure.
  GOTCHA: the `Task.yield()` sema/silgen cases must precede the generic Method_call; the spawn closure
  is owned→needs a Destroy_value to satisfy the ownership verifier. Next: **39-actors** (serialized
  isolation, builds on classes(25)+this executor), **40-macros** → project DONE.
- **Concept 39 (`phase8-arm64-backend/39-actors`) is complete and verified.** Library `swiftml_actors`
  (bin `swiftml9` repointed). Adds **`actor`** — a reference type that SERIALIZES access to its state
  — as a **compile-time ISOLATION rule** + the class runtime (an actor IS a class, concept 25). token
  (`actor` kw), ast (class_decl.is_actor), parser (`actor X {…}` parsed via parse_class, item dispatch
  `Kw_class | Kw_actor`; `is_actor = (kw.kind = Kw_actor)`), sema (the new logic): an `actors` name
  set (from is_actor class_decls) + an `in_await` flag (set while checking `Await`'s operand) +
  **THE ISOLATION RULE (learner hole TODO(39))**: a `Method_call` on `TClass cn` is rejected with
  swiftc's wording *"call to actor-isolated instance method '%s' in a synchronous nonisolated
  context"* when `Hashtbl.mem actors cn && not !in_await && !current_class <> Some cn` (outside the
  actor, not awaited). silgen/irgen UNCHANGED (actor = class). **VERIFIED vs swiftc**: a Bank actor
  (deposit/withdraw/report through `await`) → `true 120`; inside-actor self-access synchronous;
  regular `class` unaffected (`p.get()` no await); sync cross-actor call REJECTED with swiftc's exact
  diagnostic. HONEST: our executor (38) is single-threaded so RUNTIME serialization is automatic/
  degenerate — the VALUE of actors here is the compile-time rule (the part that's real + matches
  swiftc); the real per-actor serial-queue hop = exercise 5. GOTCHA: actor fields need explicit type
  + `init` (concept-25 class style: `var v: Int; init(){v=0}`, not `var v=0`). RED/GREEN is on the
  DIAGNOSTIC (skeleton wrongly accepts sync access). Tests green RED→solution (cram actor-runs-matches-
  swiftc + isolation-diagnostic + inside-sync + regular-class; 4 alcotests). Deep explainer (isolation
  = compile-time rule, the 3-condition check, in_await tracking, actor-is-a-class, the honest runtime
  note, TypeCheckConcurrency.cpp pointer) + isolation figure. Next: **40-macros** (capstone) → DONE.
- **Concept 40 (`phase8-arm64-backend/40-macros`) is complete and verified — THE CAPSTONE, PROJECT
  COMPLETE.** Library `swiftml_macros` (bin `swiftml9` repointed). Adds a **compile-time MACRO
  EXPANDER** — an `AST→AST` pass that runs BEFORE sema, so nothing downstream ever sees a macro. token
  (`Hash` `#`), lexer (`#`), ast (`MacroExpr of string * expr list * span`), parser (`#name` /
  `#name(args)` in the atom), **`macros.ml`** (new): the recursive tree walk `ex`/`exs`/`expand_program`
  (GIVEN — note: stmt variants are INLINE records → must destructure+rebuild each, can't `{r with …}`)
  + **the expansion RULES = learner holes**: `TODO(40a)` `expand_macro_expr` (`#line`→`Int_lit(line)`,
  `#column`→`Int_lit(col)`, else leave for sema to reject), `TODO(40b)` `expand_macro_stmt`
  (`#assert(cond)`→`if cond {} else { fatalError() }`). driver runs `Macros.expand_program` in
  `frontend` BEFORE `Sema.check`. `fatalError()` = a given primitive: silgen `Call("fatalError",_)`→
  `Sil.Trap` (exit 133); sema types it Void + rejects surviving `MacroExpr` ("unknown macro '#x'").
  **VERIFIED vs swiftc**: `#line`→1,2,3; nested `#line+100`/`let x=#line`/`return #line`→101,2,4
  (byte-exact); `#assert(false)` TRAPS exit 133 like swiftc's assert (BOTH lose the buffered print-
  before-trap — so we match); unknown `#nope`→clean type error. Tests green RED→solution (cram
  #line+nested+assert-trap+unknown-rejected; 4 alcotests: #line→literal, no-macro-survives, #assert→
  if/fatalError, unknown-rejected). Deep explainer (expand-before-check, the walk + the rules,
  expr-vs-stmt macros, macros compose the language's own constructs, the SE-0382/0389 + magic-
  identifiers pointer, PROJECT-COMPLETE recap) + expansion figure. v0 = built-in #line/#column/#assert
  (the MECHANISM); user-defined macros (plugin model)/hygiene/#stringify/#function + modules+
  incremental compilation = the final exercises.
- **PROJECT COMPLETE — all 41 concepts (00–40) done & verified, M0–M8 + tail all green.** From a
  single integer (Phase 0) to a Swift compiler subset: full value/reference type system (structs/
  enums/optionals/tuples, pattern matching, generics+protocols, classes+inheritance, ARC+ownership,
  closures, errors, CoW Array/String + map/filter/reduce, async/await + actors, macros); lowered
  through a real SIL + optimizer (mem2reg/SSA, fold, CSE/GVN, inline, specialize, ARC-opt) ≈ swiftc
  -O; emitted via TWO backends — the LLVM spine AND a from-scratch ARM64 backend (isel, regalloc
  ladder ~2.9× over naive, AAPCS64 ABI, peephole, DWARF debug-info); verified at every step against
  real swiftc. Phases 8's language tail (38–40) carries the FULL-LANGUAGE LLVM path (bin `swiftml9`,
  bin-lang/) — distinct from the scalar ARM64 backend (33–37, bin `swiftml8`). Whole tree builds
  clean. **Done.**
- **FULL-COURSE CRITICAL PROOFREAD done (A→Z) + a whole-program comparison suite added
  (`course/comparisons/`, `course/PROOFREAD.md`).** 20 classical programs (sorts, n-queens, RPN,
  BST-as-index-arrays, shapes/protocols, bank/errors, map-filter-reduce, matrix) compiled by BOTH
  `swiftml9` and `swiftc` at -Onone AND -O — now **20/20 byte-for-byte** (`bash comparisons/run.sh`).
  Whole programs are a far stronger oracle than the hand-picked per-concept corpora and caught
  **THREE real S1 bugs the concept tests missed, all FIXED + verified + BACKPORTED to source**: (1) `&&`/`||`
  were NOT short-circuiting (bitwise `and i1` over both operands) → `i<n && a[i]` trapped on `a[-1]`
  — now a cond_br diamond, **backported to EVERY silgen.ml from concept 08** (48 files skel+sol,
  bare-arity pre-16 / block-args 16+; verified swiftml2 bare-form + swiftml9 blockargs; RED/GREEN
  preserved — the arm is in the given gen_expr);
  (2) throwing CLASS/STRUCT methods didn't propagate (`emit_error_check` only after top-level Apply,
  not Apply_class/struct-Apply) → `try acct.withdraw()` swallowed the throw — now methods register as
  throwing (key `method:<name>`) + check after the call, **backported to every silgen.ml from concept
  30** (verified swiftml7: 70,-1 not 70,999); (3) functions
  returning/taking `[Int]` miscompiled (`ty_of_name` lacked the `[T]` case → signature TInt →
  `ret i64 %ptr`) — FIXED+backported 31/32/38/39/40 (skeleton+solution). Also FIXED this pass:
  concept-40 `macros.ml` shipped the SOLUTION not the skeleton (re-carved TODO(40a/b)); concept-40
  `sema.ml` shipped 39's actor-isolation rule as an unfilled TODO (pre-filled — `swiftml9` now
  rejects sync cross-actor calls like swiftc); concept-32 skeleton silgen missing the array-fix.
  **OPEN findings catalogued in `PROOFREAD.md`** (severity-tiered, file:line, fix sketch): `self.field=e`
  crashes in 27/28 (Set_member uses `b.vars "self"`); concept-14 silgen carry-gap crashes `swiftml3`
  on optionals; int ÷0/%0 is UB not a trap (fold comments are a false promise); `defer` inside a `do`
  doesn't fire on a locally-caught throw; large-frame prologue (stp imm overflow) miscompiles in
  33/34; `40` macro walk skips struct/enum/proto method bodies; lexer crashes on >2^62 int literals;
  `37` lldb-stepping claim is false (no `.debug_info` DIEs); `39` isolation is per-TYPE not
  per-instance; + §3 spoilers (01/32/35/36/37/39/40) and overstated parity claims (07/09/40/34).
  Reviewer agents (run per phase) ALSO swapped solutions to test RED/GREEN and, lacking git,
  RECONSTRUCTED the 01/03/04 + 05/06/07/09 skeletons from solution+§3 — functionally restored (full
  RED/GREEN matrix + clean build re-verified) but comment wording is theirs. **Suite then GROWN to 30
  programs** with 10 HARD stress tests (Sudoku backtracking solver, stack bytecode VM w/ enum-payload
  opcodes, Dijkstra, bignum 50! by array-of-digits, Game-of-Life glider, Levenshtein DP, recursive-
  descent expression parser, Kruskal MST + union-find, recursive determinant, protocols+generics+
  3-level class hierarchy) — **30/30 byte-for-byte at -Onone AND -O**. The stress programs surfaced
  one more parser divergence: **multi-line collection literals** `[\n…\n]` rejected (newline inside
  brackets = statement separator; swiftc suppresses it) — in PROOFREAD.md (fix = bracket-depth in
  lexer). Tree left consistent: build clean, skeletons RED, comparison 30/30.
- **TERNARY `a ? b : c` IMPLEMENTED + BACKPORTED (a NEW feature, not just a fix).** Full pipeline:
  ast `Ternary of expr*expr*expr*span` (+ expr_span/dump_expr), parser (single `?` in infix
  position, ternary_bp=2 = lowest, right-assoc; distinct from `??`), sema (cond Bool, arms agree →
  result type), silgen (a value-producing diamond — the general case of `&&`/`||`; slot allocated in
  the then-block, mem2reg promotes it incl. inside hot loops). Backported to **concepts 13–40** (where
  the `?` token exists), ALL of ast/parser/sema/silgen (skeleton + solution), correct Br/Cond_br
  arity per concept (bare 13–15, block-args 16+), + macros.ex (40) + fv_expr (29+). GOTCHA caught:
  the silgen arm first landed in `gen_expr_as` (a `(e,expected)` tuple match) because the "next arm"
  scan crossed a function boundary — fixed by anchoring the insert immediately BEFORE the unique
  `  | Ast.Coalesce (` gen_expr arm. Verified: swiftml6 + swiftml9 ternary parity, **31/31** suite
  (added `31_ternary.swift`: min/max/sign/clamp/recursive gcd/nested-ternary FizzBuzz) at -Onone AND
  -O, RED/GREEN preserved (13/16/25). Concept-08 explainer §6/§9 Exercise 1 retargeted ternary→`guard`
  (ternary is now shipped, so it's no longer an exercise).
- **COURSE-MAP PDF written** (`course/course-map/explainer.qmd` + `figs/make_figs.py` → pipeline.png /
  phases.png / datastructures.png; render `make explainer-pdf C=course-map`). A pedagogical
  whole-course overview: the two-oracle/two-backend design, the pipeline stage-by-stage (each stage →
  the concepts + course folder that build it), the 9-phase ladder w/ milestones, a full 00–40 concept
  index table (concept → pipeline stage → folder → what you build), how a concept dir is structured +
  the commands, and the measured milestones. Both HTML + PDF render clean. Tree consistent: build
  clean, skeletons RED, comparison 31/31.
- Build each concept's verified `solution/` only when you can run it (you can — toolchain is here).
- Prefer reading the matching `swift/lib/…` file before implementing — it's the design oracle.

## Style

Idiomatic OCaml: explicit variant types for tokens/AST/SIL, exhaustive `match`, small modules
with clear signatures (`.mli` where it clarifies the contract), `Result`/diagnostics over
exceptions for user errors (reserve exceptions for compiler bugs). Mirror the *names and structure*
of the swiftc concepts (SILGen, SILValue, BasicBlock, witness table, …) so the design oracle maps
cleanly onto our code. Write code that reads like its neighbors.

## Memory

Durable cross-session context lives in the project memory (`MEMORY.md` index). `PLAN.md` is the
source of truth for the curriculum and decisions — don't duplicate it into memory; point to it.
