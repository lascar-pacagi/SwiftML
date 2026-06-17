# 05 · Types & bidirectional inference

**Objective:** build the **type checker**. Phase 1's `sema.ml` only resolved names (everything was
`Int`). Now there are four ground types — `Int`, `Bool`, `Double`, `String` — and the checker must
infer the type of every expression, push expected types down into literals (so `let x: Double = 1`
coerces `1` to `1.0`), type the operators (`+` on numbers vs. `String`, comparisons yielding `Bool`),
and **reject** ill-typed programs with swiftc-matching diagnostics.

**Prerequisites:** Phase 1 (you've built a lexer/parser/sema/codegen once).

**You edit (three skeletons — your Phase-1 work is already filled in; you code only the new bits):**

- `lexer.ml` — Phase-1 scanning is **given and working**; `TODO(05)` holes for the new lexemes:
  string literals `"…"`, float literals `3.14`, the `:` colon, and the comparison operators
  `== != < <= > >=`.
- `parser.ml` — Phase-1 Pratt/statement parsing **given**; `TODO(05)` holes for the new prefixes
  (string/float/bool literals), type annotations (`let x: T = …`), and the comparison operators.
- `sema.ml` — the genuinely-new core: `check`, built around a **bidirectional** pair
  `infer : expr -> ty` and `check_expr : expr -> ty -> unit` (operator typing, coercion, diagnostics).

The vocabulary they produce is given as **contracts** (not yours to write): `types.ml` (the type
lattice), `token.ml` (the new token kinds), `ast.ml` (typed literals + annotations), `diagnostics.ml`.

**Design oracle:** `../../../swift/lib/Sema/TypeCheckExpr.cpp` (expression checking),
`TypeCheckConstraints.cpp`, and `CSGen.cpp`/`CSSolver.cpp` (the constraint system — Phase 5; we do the
bidirectional special case here).

## The subset this concept adds

- **Literals:** `true`/`false` (`Bool`), `3.14` (`Double`), `"hello"` (`String`), alongside `Int`.
- **Annotations:** `let x: Double = 1`, `var s: String = "hi"`.
- **Operator typing:** `+ - * / %` on `Int`; `+ - * /` on `Double`; `+` on `String` (concatenation);
  comparisons `== != < <= > >=` on matching operands → `Bool`.
- **Coercion:** an integer literal is accepted where a `Double` is expected (`let d: Double = 2`),
  mirroring Swift's `ExpressibleByIntegerLiteral`. No implicit `Int`↔`Double` on *values* (Swift is
  strict: `let i = 1; let d: Double = i` is an error — you must write `Double(i)`).

## Done when

- `make lab C=phase2-types-flow/05-types-inference` is green (cram + alcotest).
- Ill-typed programs (`let x: Int = "s"`, `1 + true`, `1 == "a"`) are rejected with the right
  diagnostics; well-typed ones pass.
- `make oracle` parity on the concept's corpus (`swiftml` accepts/rejects exactly what `swiftc` does).
