# 07 · Functions

**Objective:** add `func` declarations (parameters, an optional `-> ReturnType`, a body), `return`
statements, and calls to user-defined functions — with recursion and forward references — and
type-check them like `swiftc`: a call's arguments must match the parameter types (and count); a
`return` must match the function's return type; a non-`Void` function must return on every path
("missing return"); `return` outside a function is an error.

**Prerequisites:** concept 06. Carried forward and working; fill the `TODO(07)` holes.

**You edit (three skeletons; concepts 1–06 given):**

- `lexer.ml` — `TODO(07)`: the arrow `->` (in the `-` case, peek for `>`).
- `parser.ml` — `TODO(07)`: `parse_params` (a `(name: Type, …)` list, accepting Swift's optional
  `_` external label), `parse_func`, and the `return` statement.
- `sema.ml` — `TODO(07)`: user-function call checking (arity + arg types), `return` typing,
  `check_func` (a fresh scope with the parameters; then "missing return"), and **the two passes** —
  collect every function's signature first, then check the bodies.

**Design oracle:** `../../../swift/lib/Sema/TypeCheckDecl.cpp` (function declarations, the two-phase
name binding) and `swift/include/swift/AST/Decl.h` (`FuncDecl`, `ParamDecl`).

## The subset this concept adds

- `func name(_ a: T, _ b: T) -> R { … }` (and `-> R` omitted = `Void`)
- `return e` / `return`
- calls to user functions, **recursion**, and **forward references** (call before declaration)

> **Argument labels (a real Swift feature we simplify).** Swift requires labels at call sites:
> `func add(a: Int, b: Int)` is called `add(a: 1, b: 2)`. We call **positionally**, so the corpus uses
> the `_` ("no label") form — `func add(_ a: Int, _ b: Int)`, called `add(1, 2)` — which is what makes
> our calls match `swiftc`. Full argument-label checking is a later refinement.

Still **type-check only** (`--typecheck`); running functions needs the **SIL** backend (08–09). Each
function is its own little control-flow graph — the next concept.

## Done when

`make lab C=phase2-types-flow/07-functions` is green (cram + alcotest), and the type-check oracle
agrees with `swiftc -typecheck`: recursion and forward refs accepted; missing return, wrong arg
type/count, return-type mismatch, top-level `return`, and a Void function returning a value all
rejected.
