# 02 · parser

**Objective:** turn the token stream into an `Ast.program` with a hand-written **recursive-descent**
parser for statements/decls and a **Pratt** (precedence-climbing) parser for expressions — getting
operator precedence and associativity right.

**Prerequisites:** 01-lexer (you need a token stream).

**You edit:** `parser.ml` (in this directory) — `parse_expr_bp`, `parse_stmt`, `parse_program`. The
cursor helpers (`peek`, `advance`, `expect`), the binding-power table (`infix_bp`), and
`binop_of_kind` are already written; the AST type lives in `ast.ml` (this dir). This concept is the
**parser stage library** (`swiftml_parser`), which depends on the lexer stage for `Token` and
`Diagnostics`.

**Design oracle:** `../../swift/lib/Parse/{Parser,ParseDecl,ParseStmt,ParseExpr}.cpp`. Swift also
uses a hand-written recursive-descent parser; expression precedence is resolved by
`parseExprSequence` + the operator's precedence group (our Pratt `infix_bp` is the small version).

## Versions

| Version | What changes | Correctness |
|---|---|---|
| `v0_parse` | parse the grammar into the AST (Pratt expressions, let/var, expr statements) | `--emit-ast` golden + AST unit tests |
| `v1_recovery` *(optional)* | **error recovery**: on an unexpected token, emit a diagnostic and resync to the next newline so one error doesn't cascade | good diagnostics, multiple errors reported |

## Workflow

```bash
make explainer C=phase1-minimal/02-parser
make lab C=phase1-minimal/02-parser
dune exec swiftml -- --emit-ast tests/programs/arith.swift
```

## Definition of done

`--emit-ast` produces the correct S-expression for the corpus (precedence/associativity right:
`1 + 2 * 3` ⇒ `(+ 1 (* 2 3))`, `10 - 4 - 3` ⇒ `(- (- 10 4) 3)`), and bad input yields a sensible
diagnostic rather than a crash. Freeze `parser.ml` into `solution/`.
