# 36 · Peephole optimization & instruction scheduling

**Objective:** clean up the *final* instruction stream — the redundancy that only exists after
register allocation, as concrete register/memory traffic, which the SIL-level passes (Phase 4)
could never see. A **peephole** pass slides a small window over the machine code and rewrites
obviously-wasteful patterns: a value stored then reloaded into the same register, a slot loaded
twice, a move to self. The headline rewrite is turning a **redundant memory load into a register
move** — and the CPU largely renames those moves away for free.

**You edit:** `peephole.ml` — `TODO(36)`: `rewrite_block`, the within-block local redundant-load
elimination (track which register holds each slot, forward reloads to moves, invalidate on
clobber). The block splitting, the fixpoint driver, and the (identity) scheduler are given.

**Design oracle:** LLVM's peephole/`MachineCSE`/`MachineSink` passes and its
`PostRAScheduler` — the same "local cleanup after register allocation" stage we build here.

## What this concept adds
- **`peephole.ml`** — a per-basic-block pass that keeps a `slot → register` table and rewrites
  `ldr` of a slot whose value is already in a register into a `mov` (or deletes it when the same
  register holds it), drops `mov x, x`, and **invalidates** the table whenever a tracked register is
  overwritten or a call clobbers state. Run to a fixpoint, on by default (`--no-peephole` disables
  it, to compare).
- a **light instruction scheduler** (given, the identity) with an honest discussion of why
  reordering barely helps on out-of-order cores.

## Done when
`make lab C=phase8-arm64-backend/36-peephole-sched` green: peephole-optimized code matches `swiftc`
(and the un-optimized backend); on straight-line code that reuses variables the **load count drops**
(e.g. 18 → 11); a store-then-reload-same-register pair loses its load; and the pass is **sound**
(a clobbered register invalidates forwarding; no forwarding across a block boundary).

> **Honest scope & perf.** This removes **local** (within-block) redundancy. The *dominant* cost in
> our code — a variable reloaded at the top of every block because it lives in `alloc_stack` memory
> — is **cross-block**, and removing that needs mem2reg/SSA promotion (concept 34's exercise), not a
> peephole. So the runtime win here is small; the measurable effect is **fewer memory accesses**.
> The lesson is matching the pass to the redundancy: peephole is *local cleanup*, mem2reg is the
> *structural* fix, and instruction scheduling is ~free on Apple's out-of-order cores.
