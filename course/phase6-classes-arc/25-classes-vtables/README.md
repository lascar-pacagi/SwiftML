# 25 · Classes & vtables

**Objective:** Swift's **reference types**. `class` brings four genuinely new things at once:
**reference semantics** (a value is a *pointer* to a heap object; two bindings share one
object; fields mutate through `let` bindings), **initializers** (`init`, `super.init`, and
definite initialization), **inheritance** (fields prefix-extend, so an upcast is free), and
**dynamic dispatch through a vtable** — the per-class array of method pointers that makes an
`override` win even when the call goes through a superclass-typed variable, or through the
superclass's *own* methods.

**Prerequisites:** the full Phase-5 compiler (this concept carries it forward; protocols and
classes coexist).

**You edit:**
- `sema.ml` — `TODO(25a)`: **build the vtable** — inherit the superclass's slots, an `override`
  replaces its slot's impl *in place* (with the two swiftc diagnostics), new methods append.
- `silgen.ml` — `TODO(25b)`: **method dispatch** — slot from the *static* type's layout,
  `Apply_class` so the *object's* table decides.
- `irgen.ml` — `TODO(25c)`: **emit the dispatch** — load the object's first word (the vtable
  pointer), index the slot, load, call.

**Design oracle:** `../../../swift/lib/SIL/IR/SILVTable.cpp`,
`swift/lib/SILOptimizer/Utils/Devirtualize.cpp`, `swift/lib/IRGen/GenClass.cpp` (object layout,
header words).

## What this concept adds

- The **heap object**: `{ ptr vtable, i64 refcount, fields... }` — the refcount word is
  reserved (initialized to 1) for concept 26's ARC; `alloc_ref` mallocs and fills the header.
- **Reference semantics** end to end: `let d = c; d.bump()` is visible through `c`; `c.x = 9`
  is legal on a `let` binding (the *binding* is constant, the object isn't).
- **init**: exactly one per class (v0); definite initialization (every own field assigned,
  matching full swiftc — note swiftc runs DI at SIL level, so `swiftc -typecheck` alone won't
  show it); `super.init` required and lowered as a direct call; initializer **inheritance**
  when a subclass adds no stored properties.
- **Vtables in SIL** (`sil_vtable C { #0: @C.m … }` like swiftc's `-emit-sil`) and in LLVM
  (a global constant array per class). Self-calls inside methods dispatch dynamically — the
  probe that proves it: a superclass method calling an overridden `sound()`.
- Optimizer awareness: `Alloc_ref` is side-effecting (its lifetime is concept 26's business),
  `Apply_class` is a call, `Ref_element_addr`/`Upcast` are pure address arithmetic, vtable
  impls stay alive.

> **Scope (v0).** `var` stored properties; one explicit init; single inheritance; no
> class↔protocol conformance, no `super.method()` calls, no class `deinit` execution (declared
> in 26, where ARC gives it a meaning), no `===`/class casts (exercises). Objects **leak** —
> exactly the debt concept 26 (ARC) exists to pay.

## Done when

`make lab C=phase6-classes-arc/25-classes-vtables` is green: reference semantics observable,
the Dog vtable prints with the override replaced in place, dispatch through superclass-typed
variables (and through superclass methods) picks the override at `-Onone` and `-O`, and the
four class-shape diagnostics match swiftc.
