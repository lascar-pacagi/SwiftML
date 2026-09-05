# Critical proofread — swiftml, phases 0–8 (A → Z)

A correctness / optimization / pedagogy review of the whole course, done with the behavioral
oracle (`/usr/bin/swiftc` 6.3.2) and a new whole-program comparison suite (`comparisons/`). It
combines a focused review of every phase with the bugs the comparison suite surfaced.

**Bottom line.** The architecture is sound and the in-corpus behavior genuinely matches swiftc;
the perf claims (M4 129%, M5 103/104%, M6 126% of `swiftc -O`) reproduce. But the per-concept test
corpora are hand-picked and **systematically avoid a handful of common idioms**, so several real
bugs shipped GREEN. The pattern is the same every time: *passing ⟹ correct only if the tests
exercise the idiom.* Three such bugs were caught **only** by running classical whole programs.

Legend:  **[FIXED]** corrected + verified this pass · **[OPEN]** documented, not yet fixed.
Findings marked *concept-review pass* were closed later, during the per-concept review of
2026-09-03/04 (one commit per concept; see `git log`).
Severity: **S1** wrong output / crash / miscompile · **S2** shipped-state / carry-forward · **S3**
parity divergence (often a documented v0 limit) · **S4** docs / pedagogy.

---

## S1 — correctness (wrong output, crash, or miscompile)

### 1. `&&` / `||` are not short-circuiting  **[FIXED + BACKPORTED to all concepts]**
`silgen.ml` lowered `Ast.Binary(And/Or, …)` by evaluating **both** operands then emitting a
bitwise `and i1`/`or i1`. So the right operand's side effects always run:
`while i < n && a[i] < x` evaluates `a[i]` when `i == n` → `Fatal error: Index out of range`
where swiftc runs clean (and `false && boom()` *calls* `boom`). This breaks the single most common
array idiom. Source: **`phase2-types-flow/06-control-flow/silgen.ml`** (and every carried copy).
- *Caught by:* `comparisons/01_insertion_sort`, `04_heapsort`; independently by the phase-2 review.
- *Fix:* lower `&&`/`||` to a `cond_br` diamond that evaluates the RHS only on the deciding edge,
  merging through a stack slot (mem2reg promotes it to a phi). Applied + verified in the live
  full-language SILGen; `i<n && a[i]`, `||`, and the no-eval-on-short-path cases now match swiftc.
- *Backport DONE:* the cond_br-diamond arm is now in **every `silgen.ml` from concept 08 forward**
  (48 files, skeleton + solution), in the correct arity for each (bare `Br`/`Cond_br` pre-16,
  block-args 16+). Verified through `swiftml2` (bare form: `false && boom()` doesn't call `boom`)
  and `swiftml9` (block-args form, the comparison suite at `-O`). RED/GREEN preserved (the arm lives
  in the *given* part of gen_expr). *Pedagogy follow-up:* concept-08's explainer still lists
  short-circuit as "Exercise 1" / a v0 limitation — that note should be removed now that the given
  gen_expr short-circuits.

### 2. Throwing `class`/`struct` methods don't propagate errors  **[FIXED + BACKPORTED to 30–40]**
`emit_error_check` ran only after a top-level `Apply` (`silgen.ml`, the `Ast.Call` arm), never
after `Apply_class` or a struct-method `Apply`. So `try acct.withdraw(1000)` on a throwing method
silently swallowed the throw and fell through (printed the next statement instead of catching).
Source: **`phase7-closures-stdlib/30-error-handling`** (methods were never registered as throwing).
- *Caught by:* `comparisons/17_bank_errors`.
- *Fix DONE:* register throwing class/struct methods (keyed `method:<name>`, collision-free with
  function names) and emit the error check after the method `Apply`/`Apply_class`. Applied to
  **every `silgen.ml` from concept 30 forward** (skeleton + solution). Verified through `swiftml7`
  (`try acct.withdraw(1000)` now throws → caught → `-1`, was `999`) and the comparison suite. *Known
  limit (documented):* the `method:<name>` key is the bare method name, so two same-named methods
  where only one throws would give the non-thrower a (benign-if-no-throw) spurious check; a fully
  robust fix threads `throws` through the method signature.

### 3. Functions returning/taking `[Int]` miscompile  **[FIXED + backported]**
The signature type-resolver `ty_of_name` handled `(…)->…` and `T?` but **not** the written array
type `[T]`, so a `func f(_ a:[Int]) -> [Int]` resolved its signature to `Int` and emitted
`ret i64 %ptr` (clang: "defined with type 'ptr' but expected 'i64'"). Source: concept 31; latent in
both `swiftml7` and `swiftml9`.
- *Fix:* add the `Types.split_array_written` case to `ty_of_name`. Applied to the skeleton **and**
  solution silgen of 31, 32, and the live 38/39/40; verified array-param + array-return match
  swiftc.

### 4. `self.field = e` crashes the compiler in concepts 27 & 28  **[FIXED — concept-review pass 25–28]**
`27-ownership` made class-typed `self` a pure SSA borrow (`b.borrows`, no longer in `b.vars`), and
updated the *bare* field-write path — but the `Set_member` arm still did
`Hashtbl.find b.vars "self"` → uncaught `Not_found`. So `init(id:Int){ self.id = id }` and any
`self.x = …` in a method failed to compile (`--emit-sil`/`build`/`-O` all crashed); swiftc compiles
them. Masked because **every** phase-6 program used the bare form `id = i`.
- *Fixed:* `Set_member` now looks the receiver up in `b.borrows` first and falls back to the slot,
  mirroring the bare-field store (take_ownership / Load_take old / Destroy_value, gated on `in_init`);
  applied to `27-ownership/silgen.ml` + its `solution/` and to `28-arc-optimization/silgen.ml`.
  Pinned by a case in 27's `silgen-ossa.t` (the emitted copy/take/destroy for `Box.put`), a runtime
  case beside it, an alcotest (`fields and self`), and a corpus program in 27 and 28. Verified
  against swiftc at `-Onone` and `-O`.

### 5. `14-memory-layout` crashes on every optional program  **[FIXED — concept-review pass 4f499d6]**
Concept 14 is phase-3's latest leaf, so `swiftml3` links it — but its carried `silgen.ml` still has
concept-13's `TODO(13)` holes unfilled (`Force_unwrap`/`Coalesce`/`If_let` = `failwith`, `Nil` =
`assert false`). So `x!`, `x ?? d`, `if let` all crash through `swiftml3`. The concept-14 lab stays
green because it only tests `--emit-layout`. Same class as the 30→31 gap.
- *Fixed:* concept-13's lowering was backported into 14's carried skeleton and `solution/`, and
  14's `lab.ml` widened to swiftml3's full mode set so a cram case can exercise it. Verified:
  `dune exec swiftml3 -- build` on `if let` / `??` / `!` now matches swiftc.

### 6. Integer divide / remainder by zero is UB, not a trap  **[OPEN]** *(phases 3–4 & 2 reviews)*
IRGen lowers `Div`/`Mod` to bare `sdiv`/`srem` with no zero check; `let b=0; print(a/b)` prints
garbage and exits 0 where swiftc traps "Fatal error: Division by zero", exit 133. Worse, the
fold passes' comment ("leave ÷0/%0 for the runtime trap", `phase4-optimizer/15,17/opt.ml`) is a
**false promise** — there is no runtime trap. `Int.min / -1` is likewise LLVM-poison vs a swiftc
trap. This is a CLAUDE.md parity gotcha and is *not* in the documented-divergence set.
- *Half fixed (concept-review pass, 8b0a7f5 … 1d53e1f):* the fold comments in 15/17/18/19/20 and
  their explainers now say plainly that there is no trap and that the pass refuses to fold ÷0
  because it has no value to give, not because a trap is waiting; the corpora keep ÷0 out.
- *Still open:* the runtime behaviour. *Fix:* emit a zero-check + `llvm.trap` before `sdiv`/`srem`
  (and the `Int.min/-1` check), and add the asterisk to the "byte-for-byte" claims (09 README).

### 7. `defer` inside a `do` block doesn't fire on a locally-caught throw  **[FIXED — concept-review pass 29–32]**
`do { defer { print(2) }; try mayThrow() } catch { print(3) }` printed `3` (swiftml) vs `2`,`3`
(swiftc). `emit_error_check`'s `HJump` edge jumped straight to the catch dispatch without running
the defers of scopes between the throw and the `do` body.
- *Fixed:* `HJump` now carries the scope depth it was installed at (`HJump of int * int`), and
  every jump to a handler goes through one new given helper, `goto_handler`, which runs
  `run_defers_down_to` + `release_down_to` for the scopes the jump crosses before branching.
  `throw`, `try?`, `try!` and the post-call check all route through it. Pinned in
  `30-error-handling/tests/silgen-catch.t` (the defer-inside-`do` case, `-Onone` and `-O`), in
  `silgen-errorcheck.t` (the defer on the propagation edge), in the runtime oracle corpus, and by
  an alcotest that checks the defer body is emitted on BOTH exits. §2 now explains the depth.

### 8. Large-frame prologue is malformed (concepts 33 & 34)  **[OPEN]** *(phase 8 backend review)*
`Stp(X29,X30,SP,frame-16)` overflows STP's signed-7-bit scaled immediate (±512/504) once the frame
exceeds ~520 bytes. A ~16-local function fails to assemble at 33; a 10-local function fails under
the **default** `--regalloc=graphcolor` at 34 (frame 528 → offset 512 > 504). The default allocator
miscompiles a trivial program. Fixed only at concept 35 (push fp/lr first, then `sub sp`).
- *Fix:* backport 35's `finalize` prologue to 33 and 34 (or disclose the cap in both explainers).

### 9. `40` macro expansion skips type/struct/enum/proto method bodies  **[OPEN]** *(phase 8 tail review)*
`expand_program` walks only `IStmt`/`IFunc`/`IClass`; `IStruct`/`IEnum`/`IProto` fall through, so
`struct S { func f()->Int { return #line } }` yields "unknown macro '#line'" in `swiftml9` while
swiftc prints the line. A given-walk bug (not the learner's hole).
`phase8…/40-macros/macros.ml:99` (and `solution/`). *Fix:* also map over `s.smethods` and
enum/proto method bodies.

### 10. Smaller S1s
- **Integer-literal overflow crashes the lexer** (uncaught `Failure` from `int_of_string` on
  `> 2^62`) instead of swiftc's clean "integer literal overflows" diagnostic.
  `phase1/01-lexer/solution/lexer.ml:106`. *(phase 0–1 & 2 reviews)*
- **`missing return` false positive on `while true { return … }`** — `stmt_returns` doesn't treat
  an always-true loop as non-falling-through; swiftc accepts it.
  `phase2/07-functions/solution/sema.ml:133`. *(phase 2 review)*
- **`38` `Task{}` frees its context before the task runs** — `Spawn` emits `Destroy_value` right
  after `rt_async_spawn` (refcount 1→0, freed before the trampoline reads it). Benign only because
  v0 tasks are capture-free; a real use-after-free the moment a task captures.
  `phase8…/38-async-await/solution/silgen.ml:954`. *(phase 8 tail review)*
- **Integer overflow wraps instead of trapping** at `-Onone` (`add i64` vs `llvm.sadd.with.overflow`).
  This one *is* a documented divergence (M4 explainer) — flagged only because the 09 "byte-for-byte"
  headline doesn't carry the asterisk.

---

## S2 — shipped-state / carry-forward (all FIXED this pass)

- **`40-macros/macros.ml` shipped the *solution*, not the skeleton** (0 `failwith` holes — the
  learner opens the file to the answer). **[FIXED]** re-carved `TODO(40a)/(40b)`; lab RED-on-skeleton
  re-verified.
- **`40-macros/sema.ml` shipped concept-39's actor rule as an unfilled `TODO(39)` no-op**, so
  `swiftml9` silently accepted synchronous cross-actor calls swiftc rejects. **[FIXED]** pre-filled
  the 3-condition check (carry-forward: 39's completed rule is *given* in 40); `swiftml9 --typecheck`
  now emits swiftc's "call to actor-isolated instance method … in a synchronous nonisolated context".
- **`32-stdlib-collections/silgen.ml` skeleton was missing the array-return fix** (its solution had
  it). **[FIXED]** backported.
- *Process note:* the phase-0/1 and phase-2 reviews swapped solutions over skeletons to test
  RED/GREEN and, lacking git, **reconstructed** the 01/03/04 and 05/06/07/09 skeletons from the
  solutions + each §3 hole list. Functionally restored (full RED/GREEN matrix + clean build
  re-verified), but the reconstructed skeleton *comments* are the reviewers' wording — worth a
  glance against any originals you keep elsewhere.

---

## S3 — parity divergences (mostly documented v0 limits)

- **Newline before `else`** is rejected (`if c { } \n else { }`) though swiftc accepts it; the
  parser is newline-tolerant before `catch` but not `else`. *Caught by 03/20 in the suite.*
- **Multi-line collection literals** are rejected — a newline inside `[ … ]` was treated as a
  statement separator, where swiftc suppresses newlines inside brackets. *Caught by the sudoku/life
  stress programs (boards had to be single-line).* **[FIXED in 31/32 — concept-review pass 29–32]**
  `tokenize` tracks the `[`/`]` depth and drops `Newline` while it is above zero; pinned in
  `31-stdlib-array-string/tests/silgen-reads.t`, in its runtime and typecheck corpora, and by an
  alcotest on the token stream. Concepts 29/30 have no bracket token, so nothing to fix there; the
  same one-loop change is still wanted in the phase-8 copies (33-40), and the `( … )` half — a
  multi-line parameter or argument list — is untouched everywhere.
- **String interpolation** `"\(x)"` prints the literal `(x)` — *silent* wrong output, no diagnostic
  (should at least be rejected). *Caught while probing.*
- **`39` actor isolation is per-TYPE, not per-INSTANCE** — `current_class <> Some cn` lets a method
  of `actor A` call another `A` instance synchronously; swiftc requires `await`. Honest v0 note
  missing (cram only tests `self.`-calls).
- **`37` lldb stepping doesn't actually work** — the pass emits a correct `__debug_line` table
  (`dwarfdump` is right) but **no `__debug_info`** DIEs, which the macOS debug map/lldb require to
  bind a source breakpoint. README "Done when … lldb stepping" and the §8 lldb transcript claim a
  capability the artifact lacks. Either emit minimal CU+subprogram DIEs or rescope to
  "dwarfdump-readable line table".
- Cosmetic: `Double` prints via `%g` (`1.0`→`1`); redeclaration says `'g'` not `'g()'`;
  missing-return lacks the word "global"; a couple of 05 diagnostic wording/span offsets.

---

## S4 — documentation / pedagogy

- **§3 "Build it" spoils the answer** (verbatim solution code, violating the no-spoiler standard):
  `01-lexer`, `32-collections`, `35-mc-abi`, `36-peephole`, `37-debug-info`, `39-actors`,
  `40-macros`. Reduce each §3 to signatures + approach; the literal lines belong in §8.
- **Overstated parity claims** needing an asterisk: `07` ("missing-return oracle agrees with
  `swiftc -typecheck`" — swiftc checks at SIL level, so `-typecheck` emits nothing); `09`
  ("byte-for-byte" omits int div/overflow traps); `40` ("`#assert` traps like swiftc's assert" —
  swiftc has **no** `#assert` macro; `#line`/`#column` *are* faithful); `34` ("graph-colour ≈ 2.9×"
  is honest vs stack, but linscan ≡ graphcolor on this corpus — the top rung never climbs).
- **`03-sema` exercises** contradict the oracle: Exercise 1's hint says Swift allows top-level
  redeclaration shadowing (swiftc rejects it; §9 says the opposite); Exercise 2 is already
  implemented in the shipped solution.
- **`04-codegen`** allocas aren't hoisted to the entry block (the latent pattern that segfaulted
  concept 20 — the alloca-hoist backport skipped its IRGen origin), and the §2 figure shows
  allocas-first, mismatching the emitted IR.
- **`10-structs`** nested member write `c.p.x = 99` is an unsupported v0 boundary that produces an
  opaque parse error — worth a one-line scope note.

---

## What's genuinely clean (verified, not just asserted)

Front end: Pratt precedence/associativity, two-pass forward-ref/recursion, block scoping, the
SILGen CFG (incl. the for-loop latch). Optimizer: dominators/frontiers/pruned-SSA/renaming
(mem2reg), dominance-scoped type-aware GVN, single-block-leaf inlining, branch-fold + dead-block
elim, devirt + per-type specialization — all sound, GREEN on swap, and behavior-preserving under
`-O` on the corpus. Backend B: isel (mod=sdiv+msub, variadic-on-stack, constant materialization),
regalloc **soundness** (overlapping intervals never share a register), AAPCS64 >8-arg calls,
peephole redundant-load elimination. ARC: the two-chain destroy order, the ownership verifier
(R1/R2/R3), copy-propagation's bracket-in-lifetime safety. Perf: **M4 129%, M5 103/104%, M6 126%**
of `swiftc -O` all reproduce, and the benches verify outputs agree before timing.

And the headline: a 20-program classical suite (`comparisons/`) matches swiftc **byte-for-byte at
`-Onone` and `-O`** once the three S1 bugs above were fixed.
