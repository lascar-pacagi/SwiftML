# 22 · Generic functions

**Objective:** Swift generics — `func pick<T: Shape>(_ a: T, _ b: T) -> T`. A type parameter is a
*statically consistent* unknown: the compiler infers `T` at each call site, enforces its protocol
constraint, and — the runtime model this concept teaches — compiles **one** copy of the function
with `T` **erased to its constraint's existential**. The call boundary wraps concrete arguments in
and opens the `T`-result back out. (Cloning per concrete type — *specialization* — is concept 24's
optimization; this is the honest baseline it improves on, and it is exactly swiftc's unspecialized
path in miniature.)

**Prerequisites:** concept 21 (protocols & witness tables) — the existential machinery is reused
wholesale.

**You edit:**
- `sema.ml` — `TODO(22-sema)`: the **call-site inference**: bind `T` from the arguments, reject
  conflicting bindings (`conflicting arguments to generic parameter 'T' ('A' vs. 'B')`), enforce
  the constraint (`global function 'f' requires that 'A' conform to 'P'`), substitute into the
  return type.
- `silgen.ml` — `TODO(22-silgen)`: the **call lowering**: wrap each `T`-position argument
  (`init_existential`), call the single erased copy, `open_existential` the `T`-result when the
  inferred binding is concrete.

**Design oracle:** `../../../swift/lib/Sema/CSGen.cpp` (constraint generation for generic calls),
`swift/lib/SILGen` (the indirect/unspecialized convention), `swift/docs/Generics.rst`.

## What this concept adds

- **`<T: P>` syntax + `where T: P`** (both spellings, like Swift); type parameters scope over the
  signature and body; method calls on `T`-typed values dispatch through the constraint's witness
  table (the body already *is* concept-21 code after erasure).
- **Inference** at the call: `T` must come out the same for every `T` position, must conform, and
  flows into the result type — `let w = pick(a, b); print(w.x)` works because the caller knows
  `T = A` statically even though the callee never does.
- **`open_existential`**: the statically-checked unwrap at the call boundary (swiftc's
  `open_existential` + take, fused).

> **Scope (v0).** Single-constraint type parameters on functions. Unconstrained `<T>` is rejected
> with a clear message (it needs boxing we don't have — exercise); generic *structs* arrive with
> specialization in concept 24; multiple constraints / conditional conformances are exercises.

## Done when

`make lab C=phase5-generics/22-generics` is green: one `@pick` in SIL with `open_existential` at
the call, generic programs run (incl. `-O`) matching swiftc, and the three inference diagnostics
match swiftc's wording.
