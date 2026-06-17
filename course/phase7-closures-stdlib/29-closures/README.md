# 29 · Closures

**Objective:** function types become **first-class**. `(Int) -> Int` is a type; a closure
literal `{ (x: Int) -> Int in x + n }` is a value that **captures** its free variables; a
named function is a value too. The machinery: every function value is a **thick pair**
`{ code ptr, context ptr }` — the context is a refcounted heap object holding the captures
(null for named functions, whose ARC traffic the runtime's null-guard makes free), and every
call is `code(ctx, args)`. One calling convention for everything: that's the closure ABI.

**Prerequisites:** Phase 6 complete — contexts are refcounted objects, so function values
ride the existing ownership machinery (`TFunc` simply joins `TClass` as a *managed* type).

**You edit:**
- `silgen.ml` — `TODO(29a)`: the **lifting** — evaluate the captures by value, lower the body
  as a top-level function whose prologue binds `capture_get`s, emit the owned `Closure`.
- `irgen.ml` — `TODO(29b)`: the **indirect call** — extract code + context, call.

**Design oracle:** `../../../swift/lib/SILGen/SILGenFunction.cpp` (closure emission, capture
lowering), `swift/docs/SIL/SIL.md` (`partial_apply`, `thin_to_thick_function`),
`swift/lib/IRGen/GenFunc.cpp` (the thick-function representation).

## What this concept adds

- **Function types** in every type position — encoded canonically by the parser
  (`"(Int,Bool)->Int"`) so the string-based written-type pipeline survives; resolvers split
  with `Types.split_fn_written`.
- **Closure literals** (explicitly-typed params, single-expression bodies in v0), **by-value
  capture** (our implicit semantics match Swift's `[x]` capture lists), higher-order
  parameters, returned closures, `@escaping` parsed-and-accepted (we don't track escaping —
  a documented permissive divergence; the checker is an exercise).
- **The ownership verifier earned its keep twice more**: it caught `Closure` results not
  marked owned (leaked contexts) and `TFunc` parameters being spilled (a store consuming a
  borrow) — both fixed before any runtime test ran.

> **Scope (v0).** Single-expression bodies (multi-statement = exercise); POD captures only —
> classes and function values can't be captured (the context would need retain/destroy
> entries: exactly the value-witness story, an exercise); captures are immutable (Swift's
> `var` capture-by-reference needs boxes — the classic exercise).

## Done when

`make lab C=phase7-closures-stdlib/29-closures` is green: the lifted function, its context
layout, `capture_get` and `apply_value` visible in SIL; adders with independent contexts,
struct captures, reassigned function vars, and the closure/ARC interplay all matching swiftc
at `-Onone` and `-O`; managed-capture rejections firing.
