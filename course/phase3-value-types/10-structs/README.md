# 10 · Structs (value types)

**Objective:** add `struct` — Swift's fundamental **value type** — through the whole compiler, so
struct programs **run and match swiftc**. A struct is an aggregate of stored properties with a
memberwise initializer; the defining behaviour is **value semantics**: assigning a struct **copies**
it, so mutating the copy never touches the original.

**Prerequisites:** the complete Phase-2 compiler (01–09), given and working. This is the first
Phase-3 concept and the first time we add a whole new **type kind**.

**You edit (the value-type *lowering* — the heart of the concept):**

- `silgen.ml` — `TODO(10)`: **member read** (`p.x` → `struct_extract` from a struct value) and
  **member write** (`p.x = e` → `struct_element_addr` into `p`'s own slot, then `store`). Construction
  (`Struct`) is given.
- `irgen.ml` — `TODO(10)`: the three struct instructions → LLVM (`insertvalue` builds the aggregate,
  `extractvalue` reads a field, `getelementptr` addresses a field).

Given and complete: the contracts (`types`/`ast`/`sil` gain struct nodes), the lexer (`.` and `;`),
the parser (struct decls, member access, labeled init args), and sema (struct registry, member
typing, memberwise-init checking, member assignment).

**Design oracle:** `../../../swift/lib/SILGen/SILGenConstructor.cpp` (memberwise init), the SIL
`struct`/`struct_extract`/`struct_element_addr` instructions in `swift/docs/SIL.rst`.

## What this concept adds

- `struct Name { var a: T; let b: U }` (stored properties), the memberwise initializer
  `Name(a: …, b: …)` (labels required, in order), member access `p.x`, and member assignment
  `p.x = e` (on a `var`).
- SIL: `Struct` (build), `Struct_extract` (read), `Struct_element_addr` (field address); the module
  carries each struct's layout. IRGen emits `%Name = type { … }` and aggregate ops.
- **Value semantics** for free: a struct lives in its own `alloc_stack` slot, and `var q = p` copies
  the aggregate (`load` + `store`), so `q` and `p` are independent.

> **Scope (v0).** Stored properties + memberwise init + access + value semantics. **Methods** (with
> `self`), `mutating`, and computed properties are v1 (Exercise 1). Runtime fields are `Int`/`Bool`
> (the Phase-2 corpus).

## Done when

`make lab C=phase3-value-types/10-structs` is green: the cram test **builds and runs** struct
programs — proving value semantics (`q.x = 99` leaves `p.x` unchanged) — and the alcotest pins the
sema rules and the aggregate IR. Output matches `swiftc`.
