# 06 · Control flow

**Objective:** add branching and loops — `if`/`else` (and `else if`), `while`,
`for v in lo ..< hi`, `break`/`continue`, and the short-circuit logical operators `&&`/`||` — and
type-check them like `swiftc`: conditions must be `Bool`, `&&`/`||` take `Bool`s, the loop variable
is an immutable `Int`, blocks introduce a **lexical scope**, and `break`/`continue` are only valid
inside a loop.

**Prerequisites:** concept 05 (types & bidirectional inference). It's carried forward and working;
you only fill the `TODO(06)` holes.

**You edit (three skeletons; concepts 1–05 are given):**

- `lexer.ml` — `TODO(06)`: braces `{ }`, the logical operators `&&` `||`, and the half-open range `..<`.
- `parser.ml` — `TODO(06)`: `parse_block` (a `{ … }` block), `parse_if` (with `else`/`else if`), and
  the `while`/`for`/`break`/`continue` cases of `parse_stmt`. The `&&`/`||` precedence is given.
- `sema.ml` — `TODO(06)`: `&&`/`||` typing, and the control-flow rules — `Bool` conditions, the
  `for` variable, block scoping (the scope stack + `check_block` are given), and `break`/`continue`
  placement (via `loop_depth`).

**Design oracle:** `../../../swift/lib/Sema/TypeCheckStmt.cpp` (statement checking: condition
coercion to `Bool`, the loop context for `break`/`continue`), and `../../../swift/lib/AST/Stmt.h`.

## The subset this concept adds

- `if cond { … }` · `else { … }` · `else if …`
- `while cond { … }`
- `for v in lo ..< hi { … }` — half-open `Int` range; `v` is an immutable `Int`
- `break` · `continue` (only inside a loop)
- `&&` `||` — `Bool × Bool → Bool` (precedence: below comparisons; `&&` above `||`)

Still **type-check only** (`--typecheck`): running control flow needs codegen, which arrives with
**SIL** at concepts 08–09. Branching is exactly *why* SIL has basic blocks.

## Done when

`make lab C=phase2-types-flow/06-control-flow` is green (cram + alcotest), and the type-check oracle
agrees with `swiftc -typecheck` on the control-flow corpus (non-`Bool` conditions, `break` outside a
loop, leaking block-local bindings, mutating the loop variable, non-`Int` ranges — all rejected).
