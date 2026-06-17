# Phase 4 — The SIL optimizer (and Milestone M4)

Phases 1–3 built a *correct* compiler; Phase 4 builds a *fast* one. The deliberate debt from
concept 08 — raw, memory-based SIL, every variable a stack slot — comes due and pays off: this
phase builds the **SIL optimizer**, pass by pass, the same architecture as
`swift/lib/SILOptimizer`:

```
-O  =  inline → mem2reg (SSA) → const-fold → simplify-cfg → GVN → DCE  →  LLVM -O2
       └──────────────── our passes (15–19) ────────────────┘     └─ 20 ─┘
```

The centerpiece is **concept 16 — SSA construction from zero** (dominators → dominance frontiers
→ liveness/pruned placement → renaming), using **basic-block arguments** as the SSA form, exactly
like swiftc. Everything before it motivates it (15's folder is blind through a `load`); everything
after it cashes it in (fold/GVN/inline become powerful on SSA).

| Concept | You implement | The payoff |
|---|---|---|
| `15-pass-manager` | `run_pipeline` + a toy constant folder | the optimizer *spine*: pass = `Sil.func -> Sil.func`; `-O`, `--sil-opt` |
| `16-mem2reg-ssa` | the **renaming** walk of SSA construction | loops become `bb1(%i, %s):` block args — zero loads/stores |
| `17-constfold-dce` | `fold_binop` lattice + `simplify_cfg` | constant branches fold; unreachable blocks deleted |
| `18-cse-gvn` | `value_key` + dominance-scoped numbering | `x*x + x*x` computes the product once |
| `19-inlining` | the inline transform (splice + rename) | calls vanish; fold/CSE/DCE cascade across the old boundary |
| `20-llvm-opt` | wire `-O` → `clang -O2`; run the **M4 benchmark** | two-level optimization, honestly measured |

Each pass is verified two ways: structurally (cram on `--emit-sil` vs `--sil-opt` + alcotests) and
behaviorally (`-O` output still matches `swiftc` on a broad regression corpus — an optimizer that
changes behavior is wrong, full stop).

**Milestone M4 (measured, see `20-llvm-opt/figs/m4_bench.png`):** `swiftml -O` lands at **~129% of
`swiftc -O` speed** (geomean over the suite; 92–157% per bench) — with the honesty caveats spelled
out in concept 20's explainer (we omit Swift's overflow traps and ARC; the subset flatters LLVM).
The defensible claim: *same performance class on this subset.*
