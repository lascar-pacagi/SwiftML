# 30 · Error handling

**Objective:** `throws` / `try` / `try?` / `try!` / `do`-`catch` / `defer`. The lesson: it's all
**pure desugaring** — errors travel in a single **Int register** (`@swiftml.error`, morally
swiftc's reserved error register), so the whole feature lowers to ordinary branches plus two
runtime calls. **Zero new SIL instructions.**

**You edit:** `silgen.ml` — `TODO(30a)`: the error check after a throwing call (read the register,
branch to the current handler); `TODO(30b)`: the `do`-`catch` dispatch (compare the register to
each catch's ordinal). The `throw`/`try?`/`try!`/`defer` machinery + the `rt.error_*` intrinsics
are given.

**Design oracle:** `../../../swift/lib/SILGen/SILGenStmt.cpp` (do/catch), `SILGenExpr.cpp` (try),
`swift/docs/ErrorHandlingRationale.rst` (the typed-throws ABI).

## What this concept adds
- **error enums** (`enum E: Error`), each case assigned a global ordinal (1, 2, …; 0 = no error).
- **`throws`** functions; the desugaring: `throw` stores the ordinal + returns a discarded
  default; every throwing call reads the register and, on nonzero, **propagates** (run defers +
  ARC cleanup + return default — the register stays set for the caller) or branches to the active
  handler.
- **`do`-`catch`**: a dispatch on the ordinal (each `catch E.case` is an equality test; a bare
  `catch` matches any; the matched handler clears the register).
- **`try?`** → an `Optional` diamond (error ⇒ `.none`); **`try!`** → a `Trap` (exit 133 like
  swiftc); **`defer`** → LIFO scope cleanup, reusing the concept-26 scope stack, firing on every
  exit (fall-through, return, break/continue, throw).
- the two swiftc diagnostics: *call can throw, but it is not marked with 'try'…* and *errors
  thrown from here are not handled*.

> **Scope (v0).** Payload-free error enums; throwing functions return scalar / optional / void /
> enum (a `default_value` helper supplies the discarded throw-path result); closures don't throw.

## Done when
`make lab C=phase7-closures-stdlib/30-error-handling` green: do-catch selects by case, defers fire
LIFO (incl. throw path), `try!` exits 133, `try?` gives nil/some, and the diagnostics match —
all at `-Onone` and `-O`.
