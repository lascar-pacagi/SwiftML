# 15 · The pass manager (the optimizer's spine)

**Objective:** build the **SIL optimizer's infrastructure** — a *pass manager* that runs a *pipeline*
of transformations over the SIL — and wire up `-O` and `--sil-opt`. A **pass** is a
`Sil.func -> Sil.func` transform; the optimizer is just a list of passes the manager runs over every
function. This is Phase 4's spine: every later optimization (mem2reg, const-fold/DCE, CSE, inlining)
is a pass that plugs in here.

**Prerequisites:** the full language compiler (Phases 1–3), all **given**. The new work is the
optimizer module `opt.ml`.

**You edit:** `opt.ml` — `TODO(15)`: `run_pipeline` (the **pass manager**: run each pass over each
function, in order) and `constant_fold` (a **pass**: fold literal arithmetic to a constant). The
helper analyses (`operands`/`has_side_effect`), the `dead_instr_elim` pass (a worked example), and
the default pipeline are given.

**Design oracle:** `../../../swift/lib/SILOptimizer/PassManager/` (the SIL pass manager) and
`swift/lib/SILOptimizer/Transforms/` (the passes); swiftc's `-Onone`/`-O` and `sil-opt`.

## What this concept adds

- A pass type (`{ name; run : Sil.func -> Sil.func }`) and `run_pipeline` (the manager, with logging).
- Two small passes: **constant folding** (`1 + 2 * 3` → `7`) and **dead-instruction elimination**
  (remove pure instructions whose result is never used — e.g. the leftovers folding creates).
- CLI: `swiftml4 -O` (run the pipeline before IRGen), `--sil-opt` (print the optimized SIL),
  `--emit-sil` (raw SIL, unchanged).

> **Scope (v0).** Passes run on the raw, memory-based SIL — so constant folding can't yet see *through*
> a `let x = …; … x …` (that's a load/store). **Concept 16's mem2reg** removes those loads/stores
> (SSA), which is what makes these passes powerful. The folding here is the literal-only special case;
> concept 17 makes it real (propagation + dead-store elimination).

## Done when

`make lab C=phase4-optimizer/15-pass-manager` is green: `--emit-sil` shows the arithmetic as
instructions, `--sil-opt` shows it folded to a literal with the dead instructions gone, and **`-O`
preserves behavior** — an optimized program produces the same output as `-Onone` and as `swiftc`.
