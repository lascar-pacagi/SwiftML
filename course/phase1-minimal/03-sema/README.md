# 03 · sema (name resolution + trivial type checking)

**Objective:** walk the AST to (a) resolve names — every variable must be declared before use — and
(b) type-check. In Phase 1 the only type is `Int`, so type checking is trivial; the *point* is to
build the scope machinery and the diagnostics plumbing that Phase 2 grows into a real checker.

**Prerequisites:** 02-parser.

**You edit:** `sema.ml` (in this directory) — `check`. The `ty` type (just `TInt` for now) is
there. This concept is the **sema stage library** (`swiftml_sema`), depending on the parser stage
for `Ast` and `Diagnostics`.

**Design oracle:** `../../swift/lib/Sema/` — `TypeCheckDecl.cpp` (declarations/scope),
`TypeCheckExpr.cpp` (expressions), and later `CSGen.cpp`/`CSSolver.cpp` (the constraint solver we
build toward in Phase 5). For now you only need the scope-tracking idea.

## Versions

| Version | What changes | Correctness |
|---|---|---|
| `v0_check` | track in-scope names; reject use-before-declaration and bad `print` arity; return `TInt` everywhere | rejects what swiftc rejects |

## Workflow

```bash
make explainer C=phase1-minimal/03-sema
make lab C=phase1-minimal/03-sema
```

## Definition of done

A program that references an undeclared name produces a diagnostic matching swiftc's spirit
(`cannot find 'x' in scope`); valid programs pass; `print` with the wrong number of arguments is
rejected. Freeze `sema.ml` into `solution/`.

> Why bother when everything is `Int`? Because the *shape* — a `check_expr : env -> expr -> ty`
> that threads an environment and reports diagnostics — is exactly what Phase 2 fills with real
> types (`Bool`/`Double`/`String`), and Phase 5 replaces with a constraint solver. Build the
> skeleton now so later phases slot in.
