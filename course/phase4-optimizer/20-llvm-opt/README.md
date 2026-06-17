# 20 · LLVM -O2 & the M4 benchmark

**Objective:** close the loop. `-O` now means **two optimizers**: our SIL passes (15–19) do the
Swift-level work, then the emitted LLVM IR is compiled with **`clang -O2`** so LLVM's pass pipeline
and optimizing backend (instruction selection, register allocation, scheduling) do the machine-level
work. Then we **measure**: the M4 microbench suite times `swiftml` against `swiftc` at `-Onone` and
`-O` — the perf gate for **Milestone M4**.

**Prerequisites:** the full Phase-4 optimizer (15–19).

**You edit:** `driver.ml` — `TODO(20)`: wire `-O` through to clang (`-O2` vs `-O0`). Small on
purpose — the meat of this concept is the **benchmark**: run it, read it, and understand *why* the
numbers come out the way they do (including the honesty caveats).

**Design oracle:** swiftc does exactly this split — SIL optimizer (`swift/lib/SILOptimizer/`), then
LLVM (`swift/lib/IRGen/` hands off to LLVM's pipeline).

## What this concept adds

- **`run_clang ~opt`**: `-O` builds compile the IR with `clang -O2`; `-Onone` stays `-O0`.
- **`bench/`**: the M4 suite (`fib`, `collatz`, `primes`, `structs`, `enums`) + an OCaml runner that
  compiles each program all four ways, **verifies the outputs agree**, and times warm best-of-3 runs.
  Run: `make bench C=phase4-optimizer/20-llvm-opt`.
- **A real bug, caught by the benchmark:** IRGen emitted `alloca` inside the block where the
  `alloc_stack` appeared — so a `let` inside a hot loop grew the stack *every iteration* and a
  3M-iteration bench **segfaulted**. Fixed by hoisting every alloca to the entry block (what clang
  does). The alcotest pins the fix.

## Results (M4 — measured, see `figs/m4_bench.png`)

`swiftml -O` ≈ **129% of `swiftc -O`** speed (geomean; 92–157% per bench). **Read the explainer's
honesty section before celebrating** — swiftml omits Swift's integer-overflow traps (and ARC), so
part of that edge is skipped safety work, not better optimization.

## Done when

`make lab C=phase4-optimizer/20-llvm-opt` is green (`-O` builds run correctly, the hot-loop alloca
case doesn't crash) and `make bench C=phase4-optimizer/20-llvm-opt` reports `-O` beating `-Onone` on
every program with `swiftml -O` in the band of `swiftc -O`. **That's Milestone M4.**
