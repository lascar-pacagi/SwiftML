# 40 · Macros — compile-time code that writes code (the capstone)

**Objective:** the project's final piece — a **macro expander**: a compile-time `AST → AST` pass
that runs *before* the type checker, turning `#line` into an integer literal and `#assert(c)` into a
conditional trap. Macros are *code that writes code*; the compiler's job is to expand them into
ordinary AST that the rest of the pipeline — sema, SILGen, the backends — type-checks and lowers as
if you'd written the expansion by hand. This is exactly swiftc's macro model, at teaching scale.

**You edit:** `macros.ml` — `TODO(40a)`: `expand_macro_expr` (the expression macros `#line`/`#column`
→ integer literals); `TODO(40b)`: `expand_macro_stmt` (`#assert(c)` → `if c { } else { fatalError()
}`). The recursive AST walk that reaches every macro, and the `fatalError()` trap primitive, are
given.

**Design oracle:** Swift macros (`SE-0382`/`SE-0389`), `#line`/`#column`/`#function` (the magic
identifiers), and the principle that macros expand *early*, as a syntactic transform, so the
expansion is checked like ordinary code.

## What this concept adds
- **A macro syntax** (`#name` and `#name(args)`) and the AST node for it.
- **The expander** — a pass (`Macros.expand_program`) wired into the front end *before* `Sema.check`,
  so no macro ever reaches the type checker; it only sees the expansion.
- **Built-in macros:** `#line` / `#column` → the source location (integer literals, like swiftc's
  magic identifiers); `#assert(cond)` → a conditional `fatalError()` trap (exit 133 on false, like
  swiftc's `assert`). Unknown macros survive expansion and are rejected by sema.

## Done when
`make lab C=phase8-arm64-backend/40-macros` green: `#line`/`#column` produce the right numbers
(matching `swiftc`), nested in ordinary expressions; `#assert(false)` traps (exit 133) like swiftc's
`assert`; an unknown macro is a clean type-error.

> **Scope (v0).** Built-in **expression** macros (`#line`/`#column`) and one **statement** macro
> (`#assert`) — the expansion *mechanism* (`AST → AST`, before sema), which is the lesson. A real
> macro system additionally lets *users define* macros (a separate compiler plugin that receives the
> argument syntax and returns generated syntax — `#stringify`, `@Observable`, …), with hygiene
> (generated names that can't capture). That plugin model, plus the survey of **modules/imports** and
> **incremental (rebuild-only-changed) compilation** that round out a real toolchain, are documented
> as the final exercises.
