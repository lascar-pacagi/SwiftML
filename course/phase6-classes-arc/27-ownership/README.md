# 27 · Ownership SSA

**Objective:** make concept 26's invisible discipline *visible and checkable in the IR*. Raw
`retain`/`release` become **structured ownership operations** — `copy_value` (a borrow becomes
a new +1 owner), `destroy_value` (consume an owned value), `load [take]` (ownership moves out
of dying storage, for free) — and every class-typed value gets an **ownership kind**: OWNED
(carries +1, must be consumed exactly once) or GUARANTEED (a borrow, never consumed,
no traffic). Then the **ownership verifier** enforces it on every compile: leaks,
double-frees, destroyed borrows, and use-after-consume become *compile errors*. This is
swiftc's OSSA (Ownership SSA) in miniature — and the structure concept 28's ARC optimizer
spends.

**Prerequisites:** concept 26 (the ARC runtime; behavior is *unchanged* by this recast — the
full deinit-parity suite re-verifies it).

**You edit:** `sil.ml` — `TODO(27)`: the **verifier** (`verify_ownership`): classify values
(given predicates: `def_is_owned`, `consumed_operands`, `consumed_by_term`), report R1
(exactly-once), R2 (never consume a borrow), R3 (no use after consume). The driver runs it on
every compile — concept 26's insertion must satisfy your verifier.

**Design oracle:** `../../../swift/docs/SIL/Ownership.md`,
`swift/lib/SIL/Verifier/SILOwnershipVerifier.cpp`, `swift/lib/SIL/IR/OperandOwnership.cpp`.

## What this concept adds

- **`copy_value` / `destroy_value` / `load [take]`** replacing raw retain/release in SILGen —
  same machine code (a copy lowers to a retain; a take is a plain load), but the IR now says
  *why* each operation exists.
- **Guaranteed parameters never touch memory.** The verifier immediately caught our own
  SILGen spilling class params to stack slots (the entry `store` consumes a borrow — R2!).
  The fix is the real OSSA design: class-typed parameters (including `self`) stay pure SSA
  values, used directly. The verifier improved the compiler before the concept was even done.
- **The verifier**, run on every compile, with hand-built bad SIL in the tests proving it
  catches all four violation classes (source code can't express them — generated SIL is
  always clean; the IR can).

> **Scope (v0) — honestly stated.** Exactly-once is checked function-wide, not per-path (our
> SILGen emits exactly one consumer per owned value; the path-sensitive version is the real
> verifier's dataflow). Use-after-consume is checked within a block. Exclusivity checking
> (Swift's "no overlapping access") needs `inout`/`mutating`, which we don't have — exercise.

## Done when

`make lab C=phase6-classes-arc/27-ownership` is green: the structured ops appear in
`--emit-sil`, class params take no slots, behavior is unchanged (deinit order matches swiftc
at `-Onone` and `-O`), and the verifier accepts all generated SIL while rejecting the four
hand-built violations with the exact messages.
