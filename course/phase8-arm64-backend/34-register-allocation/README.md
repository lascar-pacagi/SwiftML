# 34 · Register allocation — the ladder

**Objective:** make Backend B fast. Concept 33's stack machine spilled *every* value to memory;
this concept keeps values in **registers**. It's the flagship Phase-8 lesson, built as a runnable
**ladder** — three rungs, each correct, each beating the last:

```
v0 STACK         spill every value to its slot (≈ concept 33). correct, slow.
v1 LINEAR-SCAN   assign over live intervals; spill the interval ending latest under pressure.
v2 GRAPH-COLOUR  interference graph + simplify/spill/select (Chaitin–Briggs).
```

isel now emits over **virtual registers** (each SIL value → a `Virt`); the allocator maps them to
**physical** registers or spills. The pool is the **callee-saved** registers `x19`–`x27`, so any
allocated value survives a `bl` for free (no call-clobber modelling); `x9`–`x14` stay scratch for
the spill rewrite; a "spill" just means "live in the value's own frame slot."

**You edit:** `regalloc.ml` — `TODO(34a)`: `linscan` (the linear-scan core); `TODO(34b)`:
`graphcolor` (the colouring core). Liveness, live intervals, the vreg→physical rewrite, frame
finalization (prologue/epilogue saving the used callee-saved registers), and the v0 stack rung are
given. Pick the rung with `--regalloc=stack|linscan|graphcolor` (default graph-colour).

**Design oracle:** the LLVM AArch64 register allocator (greedy); Poletto & Sarkar's *Linear Scan
Register Allocation*; Chaitin / Briggs on graph-colouring — the two classic algorithms you build.

## What this concept adds
- **`isel.ml`** re-emitting over virtual registers (no prologue/epilogue — finalized after
  allocation); **`regalloc.ml`** with liveness, live-interval construction, the two allocators, the
  spill rewrite, and frame finalization.
- `--regalloc` to select a rung; a `bench/` comparing all three (+ the LLVM `-O` path).

## Done when
`make lab C=phase8-arm64-backend/34-register-allocation` green: all three rungs produce native
binaries matching `swiftc`; graph-colour has far less load/store traffic and uses callee-saved
registers where stack uses none; allocation is **sound** (no two simultaneously-live values share a
register). `make bench C=phase8-arm64-backend/34-register-allocation`: each rung beats the last —
**graph-colour ≈ 2.9× faster than stack (geomean)**, reaching ~45% of our LLVM `-O` path (the gap
is variables still living in memory — promoting them needs mem2reg, the documented next step).

> **Scope (v0).** Same Int/Bool + control-flow + functions corpus as concept 33 (we lower the raw
> `-Onone` SIL, so variables stay in `alloc_stack` memory and only the *temporaries* get registers
> — running mem2reg first to promote variables is the exercise). On low-pressure code linear-scan
> and graph-colour coincide; they diverge when live values exceed the 9-register pool.
