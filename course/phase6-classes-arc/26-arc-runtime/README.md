# 26 · The ARC runtime

**Objective:** pay concept 25's debt. Every object gets a managed lifetime: **retain** on every
new owner, **release** when an owner lets go, and at refcount zero the **deinit** runs and the
memory is freed — with swiftc's exact deinit **timing and order** as the oracle (the heart of
Milestone M6). The refcount word has been sitting in the object header since 25; this concept
makes it mean something.

**Prerequisites:** concept 25 (classes, vtables, the header layout).

**You edit:**
- `silgen.ml` — `TODO(26a)`: the **ownership-transfer rule** (`take_ownership`): a fresh +1
  temp is *consumed* by its new owner; a borrowed value gets a *retain*. One wrong way =
  use-after-free; the other = leaks.
- `silgen.ml` — `TODO(26b)`: the **field-destroy chain** (`C.destroy`): super first (base
  fields die before derived's — probed!), then own class-typed fields.
- `irgen.ml` — `TODO(26c)`: **`rt.release`** — decrement; at zero call vtable slot 0 (deinit
  bodies), slot 1 (field destroy), then `free`.

**Design oracle:** `../../../swift/stdlib/public/runtime/HeapObject.cpp` (`swift_retain`/
`swift_release`), `swift/lib/SILGen/SILGenDecl.cpp` (the cleanup stack),
`swift/docs/ARCOptimization.md` (read it now — it's concept 28's spec).

## What this concept adds — the ARC insertion rules (all probed against swiftc -Onone)

| event | rule |
|---|---|
| fresh value (`T(1)`, owned call result) | born +1; a **statement temp** until consumed |
| stored into a local / field | **consume** the temp, or **retain** a borrowed value |
| statement ends | release unconsumed temps |
| scope exits (incl. `return`/`break`/`continue`) | release class-typed locals, **newest first** |
| reassignment | evaluate new, take it, store, **then** release old (old deinit after new init) |
| `return v` | +1 to the caller (retain a borrowed `v` *before* the scope releases) |
| call arguments | **borrowed** (caller keeps them alive — no traffic) |
| top-level `var`s | **never released** (globals; swiftc runs no deinit at exit) |
| deallocation | deinit **bodies** derived→base, then **fields** base→derived, then free |

The deallocation order is the concept's subtlest finding: a first implementation ran each
level's fields right after its body — swiftc disagreed (`2000, 1003, 7`, not `2000, 7, 1003`),
so the destructor is **two chains** (vtable slots 0 and 1, walked in opposite directions).

> **Scope (v0).** Class references may not appear inside structs/enums/optionals (bitwise
> copies would corrupt counts — sema rejects, with the value-witness machinery as the path to
> lifting it). Reference CYCLES leak, exactly like real Swift (`weak` is an exercise). The
> retain/release traffic is naive-but-correct — making it cheap is concept 28.

## Done when

`make lab C=phase6-classes-arc/26-arc-runtime` is green: deinit order matches swiftc across
scopes, reassignment, shared objects, inheritance chains, cross-level fields, loops, early
returns and breaks — at `-Onone` **and** `-O` (no pass may drop or reorder refcount traffic).
