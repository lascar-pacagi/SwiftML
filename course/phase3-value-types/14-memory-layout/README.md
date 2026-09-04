# 14 · Memory layout

**Objective:** how a value type sits in memory — its **size**, **alignment**, **stride**, and
each stored property's **byte offset**. The rules are universal (natural alignment + padding);
the numbers match swiftc's `MemoryLayout<T>` *exactly* for structs of scalars. (This is the
Phase-3 layout chapter, backfilled — it branches off `13-optionals`.)

**You edit:** `layout.ml` — `TODO(14a)`: the struct **padding walk** (`struct_info` — fields in
order, each padded to its own alignment); `TODO(14b)`: the **field offsets** (the same walk,
remembering each start). The dispatch + scalar/enum/optional sizes + `stride` are given.

**Design oracle:** `../../../swift/docs/ABI/TypeLayout.rst`, `swift/lib/IRGen/GenStruct.cpp`,
and `MemoryLayout<T>.size`/`.stride`/`.alignment`/`.offset(of:)` (the behavioral oracle).

## What this concept adds
- `--emit-layout`: dump size/stride/align of every scalar and declared struct/enum + field offsets.
- The **size vs stride** distinction (size = past the last field; stride = size rounded to
  alignment = array element spacing); **alignment** = max of the fields'; **padding** inserted so
  each field lands on a multiple of its alignment — which is why `{Int; Bool}` is 9 bytes but
  `{Bool; Int}` is 16.

> **Parity & honesty.** Structs of `Int`/`Bool`/`Double` match swiftc byte-for-byte. **Enums and
> optionals use swiftml's naive `{i64 tag, payload}` model** — swiftc packs the tag into the
> payload's *spare bits* (so `Optional<SomeClass>` is pointer-sized with `nil` = null). That
> spare-bit packing is the explainer's "how swiftc does it" — a documented divergence, not a bug.

## Done when
`make lab C=phase3-value-types/14-memory-layout` is green: `layout-padding.t` (sizes, strides,
alignments) and `layout-offsets.t` (the field offsets) — both driven by `--emit-layout`, so they
go green together, with the per-hole reading in the alcotest — and `oracle.t`, where our output
for each of 16 struct programs is turned into a `MemoryLayout<T>` probe, compiled and run by
`swiftc`, and compared byte for byte.
