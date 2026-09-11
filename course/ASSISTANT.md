# Working on this course with an AI assistant

Paste this file (or point the assistant at it) at the start of a session. It is written for any
assistant — Codex, Claude, whatever — and assumes nothing but a shell in `course/`.

Read `CLAUDE.md` next: it is the operational guide and this file does not repeat it. What follows
is the part that is hard to infer from the repo, and the standing rules that took a while to
learn.

---

## What this is

A learn-by-doing build of **the Swift compiler, from scratch, in OCaml**, in 41 concepts
(`00`–`40`) across nine phases. Each concept is a complete compiler for a growing subset:
`Parse → Sema → SILGen → SIL → optimizer → IRGen → LLVM → native`, plus a second, from-scratch
ARM64 backend in Phase 8.

Two oracles, both **read-only**:

* `swift/` — Apple's compiler source. The **design** oracle: read it, mirror its architecture,
  never edit it.
* `/usr/bin/swiftc` (6.3.2) — the **behavioural** oracle. Compile the same `.swift` with it and
  with ours; stdout and exit code must agree.

I am the author *and* the learner. The course is finished and verified; I am now working through
it as a student, filling the `TODO(NN)` holes myself.

---

## The two roles, and the line between them

**Mine.** The `TODO(NN)` holes in each concept directory (`lexer.ml`, `parser.ml`, `sema.ml`,
`silgen.ml`, `irgen.ml`, …). Do not fill them, do not "fix" them, do not paste the answer from
`solution/`. If I am stuck, ask what I have tried, point at the section of the explainer that
covers it, or name the one fact I am missing — the way you would with a colleague, not a grader.

**Yours.** Everything else: explainers, tests, tooling, contracts (the given parts of those same
files), `PROOFREAD.md`. Course fixes are committed to `main` normally. **My solutions are never
committed.** If a fix has to touch a file I am working in, say so first, and keep the change to
the given part.

If you are running in a harness that forces a git worktree, your commits land on a branch, not in
my checkout. Finish the job: leave the worktree, `git merge --ff-only <branch>` from the repo
root, and re-run `make explainer C=<dir>` **in my checkout** — the rendered HTML/PDF are
gitignored, so a render done inside the worktree stays there and I will keep reading a stale PDF.
If my working copy has changes to a file your merge touches, back it up, merge, then restore
**my** file as the base and re-apply only what the merge added to it. Losing my work by taking
the merged file as the base has happened; do not repeat it.

---

## How I work, and what I want from you

I read the explainer, fill the holes, run `make lab`, and come back with questions like *"is this
test good or is it me?"*, *"why does this fail?"*, *"this sentence is unclear"*, *"this name is
misleading"*. Expect all four, often about your own earlier work.

- **Answer the question asked.** If I ask whether `X` is possible, answer that, then add what
  matters. Do not restructure things I did not ask about.
- **Check, do not assert.** Run the code, run `swiftc`, read the file. Every claim in this course
  is supposed to be verified; "I believe" is not a result. When I say something is wrong, test it
  before agreeing *and* before disagreeing.
- **Say plainly when I am wrong,** and when you are. Both happen. A verified counter-example ends
  the discussion faster than either of us arguing.
- **Be concise in prose.** I will tell you when something is too verbose — I have, repeatedly.
  Short sentences, one idea each. No preamble.
- **Explain Swift as we go.** I am a professional programmer but new to Swift; gloss language
  features when they first appear (`Void` is a typealias for the empty tuple, argument labels
  vs parameter names, and so on).

---

## The bar for tests — this is the part that keeps biting

`passing ⟹ correct`, and the contrapositive matters just as much: **a failing test must mean the
code is wrong.** Four times in one session a test failed on a correct solution because it pinned
an arbitrary choice of the reference implementation rather than the rule it claimed to check:

* an assertion looking for the loop bound in `bb0` by index, when "computed once, outside the
  loop" was the requirement;
* a latch located by "not block 0", which a loop's setup block also satisfies;
* `(a)` in a parameter list demanding one of two equally defensible diagnostics;
* full-text SIL goldens that encoded block numbering, which follows the order blocks happen to be
  created in.

When a test fails on work you have not seen before, **the first question is which of the two is
wrong.** Read the case's own sentence: it states the claim, and if the assertion checks something
narrower, the assertion is the bug. Concept 08 now has `--emit-sil-canon` (`tests/canon.ml`,
tested by `tests/test_canon.ml`) precisely for this: control-flow goldens compare a normal form,
so two lowerings that build the same graph compare equal.

Other standing rules, all learned the hard way:

- **Goldens are produced, never written.** Run the case against `solution/` and paste what it
  prints. A hand-written expectation is how a test ends up asserting the wrong thing.
- **One `.t` per hole**, each case named by a claim sentence, so a finished hole shows up by name.
  `TODO` means every failing case reached an explicit unwritten `TODO(NN)`; `FAIL` means the test
  ran and found wrong output or a crash; `SKIP` means it never ran. Never report a test that did
  not run as passing.
- **A hole must be gradeable on its own.** If a test can only go green once a *later* hole exists,
  that is a defect — give the hole its own entry point (`--emit-params`, `--emit-returns`,
  `--emit-sil-canon` all exist for this reason).
- **Prove RED/GREEN before believing a test.** Skeleton must fail, `make check-solution` must
  pass. That command uses an isolated worktree; never replace my live files, even temporarily.
- **`dune --auto-promote` rewrites every golden in the directory.** Only ever run it inside an
  isolated answer-key worktree, or it will happily record learner output as the expected answer.

---

## Commands

Run from `course/`. The toolchain is the opam switch, so `dune` goes through `opam exec --`
(the `Makefile` already does).

    make build                             # whole tree
    make lab C=phase2-types-flow/08-sil-silgen         # one concept's tests, formatted
    make lab C=<dir> T=silgen-for          # one cram file
    make lab C=<dir> DETAIL=1              # diffs even for an untouched hole
    make check-solution C=<dir>            # swap solution/ in, run, restore — the answer key
    make oracle F=prog.swift B=swiftml9    # differential vs swiftc
    make explainer C=<dir>                 # HTML   (also: explainer-pdf)
    bash comparisons/run.sh                # 32 whole programs, ours vs swiftc, -Onone and -O

`make test` on the shipped tree is RED by design — the skeletons' TODOs fail their own tests.

---

## Where I am

Phase 2, **concept 08 (`08-sil-silgen`)** — SILGen, the AST → SIL lowering. Its holes:

* `TODO(08a)` — the memory model: a variable is an `alloc_stack` slot, read with `load`, written
  with `store`. **Done.**
* `TODO(08b)` — the ordinary binary operator: two types are in play, the one the operation happens
  *at* and the one it produces (`result_ty`). **Done.**
* `TODO(08c)` — the control flow: the `if` diamond, the `while` loop, `for` desugared to a counted
  loop with a latch, and `break`/`continue` reading the loop stack. **Done.**

`make lab C=phase2-types-flow/08-sil-silgen` is 10 passing, 0 failing. Next is concept 09
(`09-sil-to-llvm`), where the SIL finally runs.

Earlier concepts (01–07) are also filled in in my working copy.

---

## Things about this codebase that surprise people

- **`Types.of_name` and `Types.string_of_ty` are not inverses.** Source writes `Void`; a
  diagnostic prints `()`. So `of_name (string_of_ty TVoid)` is `None`, and a function with no
  `-> T` is `TVoid` directly rather than a name to resolve.
- **`Sil.Unreachable` is a real terminator** *and* the value a block's terminator has until one is
  set. `terminate` keeps the **first** terminator, so a `br` emitted after a `return` is ignored.
- **`emit` numbers every instruction, including ones with no result**, which is why printed SIL
  skips a `%n` at a `store`. `emit_void` is the helper for those.
- **A block is a scope for *names*.** `gen_block` saves and restores `vars`, or an inner
  `var x` would shadow the outer one permanently. The slots are not scoped; only which address a
  name means.
- **The keyword table lives in `token.ml`**, not `lexer.ml`. Editing the wrong one silently
  does nothing.
- Cram has no `(re)`/`(glob)`; `grep -c` exits 1 on a count of 0 (`|| true`); a signal-killed
  binary needs `sh -c './t; echo "exit=$?"' 2>/dev/null` or the shell's "Trace/BPT trap" line
  lands in the golden.
- After editing `token.ml` or `lexer.ml`, build without `--no-build` — a stale binary will lie
  to you.

---

## Known-open problems

`PROOFREAD.md` is the list, severity-tiered with file:line and a fix sketch. The live ones:

* **Backend B does not trap on division by zero.** The LLVM path does (helper in the IRGen
  preamble, `Fatal error: Division by zero`, exit 133); the ARM64 path lowers `sdiv`/`msub`
  directly and never sees the guard. `Int.min / -1` is poison in both.
* **An array stored property mutated through a method crashes SILGen** (`assert false`) instead of
  producing a sema diagnostic.
* **String interpolation `"\(x)"` prints the literal `(x)`** — silently wrong, should at least be
  rejected.
* `e as T` accepts only the five scalar type names, so `p as P` for a struct is rejected where
  swiftc accepts it — the ascription path resolves types differently from annotations.
* Concept 39's actor isolation is per-*type*, not per-*instance*; concept 37 emits a line table
  but no `__debug_info`, so lldb cannot bind a breakpoint. Both documented and pinned rather than
  fixed.
