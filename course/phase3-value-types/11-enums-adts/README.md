# 11 · Enums (ADTs / tagged unions)

**Objective:** add `enum` — Swift's **sum type** — so enum programs **run and match swiftc**. Where a
`struct` is a *product* ("all of these fields at once"), an `enum` is a *sum* ("exactly one of these
**cases**"), represented as a **tagged union**: a **tag** (which case) plus a **payload** sized to the
widest case. Together, structs and enums are *algebraic data types*.

**Prerequisites:** the struct compiler (concept 10), given and working. Enums are a second new type
kind, threaded the same way.

**You edit (the enum *lowering*):**

- `silgen.ml` — `TODO(11)`: **construct** an enum value — `E.case` (no payload) and `E.case(args)`
  (payload) → `Sil.Enum (tag, payloads)`, where `tag` is the case's index.
- `irgen.ml` — `TODO(11)`: the enum instructions → LLVM (`Enum` builds the aggregate
  `{ i64 tag, payload… }` with `insertvalue`; `Enum_tag` reads field 0 with `extractvalue`).

Given: the contracts (`types`/`ast`/`sil` gain enum nodes), parser (enum decls, `E.case(args)`), and
sema (enum registry, case typing, raw values, the `Equatable` rule).

**Design oracle:** `../../../swift/lib/SIL/` (the `enum`/`unchecked_enum_data` instructions),
`swift/docs/SIL.rst`; `swift/lib/IRGen/GenEnum.cpp` for the real (spare-bit-optimized) layouts.

## What this concept adds

- `enum Name [: Int] { case a; case b(Int, Int); case c }` — simple, raw-value, and associated-value
  cases (one `case` line may list several: `case red, green, blue`).
- Construction (`Color.red`, `Shape.circle(5)`), `.rawValue` (raw-value enums → the tag), and `==`
  (tag comparison; **payload-free enums only** — see below).
- SIL: `Enum` (build), `Enum_tag` (read the tag); the module carries each enum's layout. IRGen emits
  `%E = type { i64, i64×payload }`.

> **Scope (v0).** Payloads are `Int`; implicit raw values (`= index`). **Destructuring associated
> values needs `switch` — that's concept 12**, which is why enums and pattern matching are a pair.
> Matching swiftc: a payload-free enum is implicitly `Equatable` (so `==` works); an associated-value
> enum's `==` is **rejected** unless it declares `: Equatable` (deferred), exactly as swiftc does.
> Two rules are stricter than swiftc and stay out of the oracle: `print` of a whole enum (swiftc
> prints the case name through reflection) and `E.a` naming a payload case with no arguments
> (swiftc reads it as the case's constructor *function*) — the explainer's diagnostics table lists
> the honest set.

## Done when

`make lab C=phase3-value-types/11-enums-adts` is green: one cram file per hole
(`silgen-case.t`, `silgen-payload.t`, `irgen-enums.t`, each `TODO` until you start it) plus the
given `sema-enums.t`, the alcotest's four groups, and `oracle.t` — 16 programs compiled by `swiftc`
and by `./lab.exe build`, run, and compared byte for byte, and 18 more where `swiftc -typecheck`
and `--typecheck` must reach the same verdict.
