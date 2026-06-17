# 23 · Existential containers & dynamic casts

**Objective:** open the box. Concept 21's existential cheated — it sized the payload buffer to
the *largest conformer*, a whole-module trick swiftc can't use (a new conformer can live in
another module). This concept adopts **swiftc's real container**: a **fixed 3-word inline
buffer** plus the witness-table pointer; values that fit live inline, larger ones are
**heap-boxed**. On top of the honest container: **dynamic casts** — `e as? T` (conditional,
yields `T?`) and `e as! T` (forced, aborts on mismatch like swiftc, exit 134) — implemented by
**type identity = witness-table identity**.

**Prerequisites:** concepts 21–22 (the existential machinery and `open_existential`).

**You edit:**
- `silgen.ml` — `TODO(23a)`: lower `as?` (an `Optional<T>` built across a diamond — the
  coalesce pattern) and `as!` (test-or-`Abort` — the force-unwrap pattern).
- `irgen.ml` — `TODO(23b/c)`: the **inline-or-box** write in `init_existential` (malloc + store
  for big types) and the matching read in `open_existential`.

**Design oracle:** `../../../swift/docs/ABI/TypeLayout.rst` (the existential container),
`swift/lib/IRGen/GenExistential.cpp`, `swift/stdlib/public/runtime/Casting.cpp` (`as?`).

## What this concept adds

- The **fixed-size container** `{ [3 x i64], ptr }` for every existential — identical layout for
  every protocol, which is what separate compilation requires. `is_boxed` is decided per
  concrete type at compile time; witness thunks for boxed types unbox before calling.
- **`as?` / `as!`** with swiftc's semantics: success/failure decided by the *value's* table
  pointer; casts to unrelated types compile with swiftc's warning and always fail; `as!`
  mismatch aborts (SIGABRT/134 — distinct from force-unwrap's SIGTRAP/133).
- The `--typecheck` driver now prints **warnings** too (the always-fails cast warning).

> **Scope (v0) — honestly stated.** Our payloads are immutable PODs, so (a) boxes are *shared*
> on copy (safe: no mutation through existentials — this is copy-on-write with no writes), and
> (b) boxes are **never freed** — reclaiming them needs reference counting, which is Phase 6
> (ARC). The **value witness table** — swiftc's per-type record of size/copy/destroy functions
> that makes all this work for non-POD types — is taught in the explainer and becomes real in
> Phase 6; our degenerate POD version needs only the size, which is static.

## Done when

`make lab C=phase5-generics/23-existentials` is green: a 5-word conformer round-trips through
functions, reassignment, casts and `-O`; `as?` discriminates by value; the unrelated-cast warning
matches swiftc's wording; `as!` failure exits 134.
