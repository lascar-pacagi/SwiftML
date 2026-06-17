# 17 · Constant folding & dead-code elimination

**Objective:** turn concept 15's toy passes into the real thing — now that **mem2reg** (16) gives us
SSA, they're powerful. Generalize **constant folding** to comparisons and bools, propagate constants
through SSA values, and add **CFG simplification**: fold a branch whose condition is a known constant,
then delete the block that just became unreachable.

**Prerequisites:** the pass manager (15) and mem2reg (16). The optimizer module, the basic
`constant_fold`/`dead_instr_elim`, and `mem2reg` are given.

**You edit:** `opt.ml` — `TODO(17)`: `fold_binop` (evaluate a binary op on two constants — Int
arithmetic, integer/bool comparisons, `&&`/`||`) and `simplify_cfg` (fold a `cond_br` on a constant
condition to a `br`, then delete blocks unreachable from the entry).

**Design oracle:** `../../../swift/lib/SILOptimizer/` (the SCCP / SimplifyCFG / DCE passes); LLVM's
`-instcombine`/`-simplifycfg`.

## What this concept adds

- **Constant folding** over a small lattice (`CInt`/`CBool`): arithmetic → `Int`, the six comparisons
  → `Bool`, `&&`/`||` → `Bool`, unary `-` → `Int`. (`÷0`/`%0` are *not* folded — the runtime trap is
  preserved.) On SSA, a `let x = 5` is already the value `5`, so folding propagates through it.
- **CFG simplification**: `cond_br %c, …` with `%c` constant becomes an unconditional `br` to the taken
  side; the other block, now unreachable, is removed. The pipeline repeats fold→simplify so a folded
  branch exposes more folding.

## Done when

`make lab C=phase4-optimizer/17-constfold-dce` is green: `3 < 5` folds to `true` in `--sil-opt`,
`if 10 > 3 { … } else { … }` loses its `cond_br` and its dead `else` block, and **`-O` still matches
`swiftc`** across constant-heavy programs and real loops.
