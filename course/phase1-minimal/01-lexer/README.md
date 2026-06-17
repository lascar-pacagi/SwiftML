# 01 · lexer

**Objective:** hand-write the lexer — turn the source string into a stream of `Token.t`. This is
the compiler's mouth: every later stage eats tokens, not characters.

**Prerequisites:** Phase 0 (toolchain builds).

**You edit:** `lexer.ml` (in this directory) — the function `next` (the scanning DFA). `tokenize`
(the driver loop) and the cursor helpers are already written; the token type lives in `token.ml`
(this dir), and `diagnostics.ml` (also here) is the shared error sink. These three files make up
the **lexer stage library** (`swiftml_lexer`); the parser stage depends on it.

**Design oracle:** `../../swift/lib/Parse/Lexer.cpp` (`Lexer::lexImpl`, `lexNumber`,
`lexIdentifier`, comment handling) and `../../swift/include/swift/Parse/Token.h`.

## Versions

| Version | What changes | Correctness | Perf |
|---|---|---|---|
| `v0_naive` | a clean `match peek_char` DFA: whitespace/comments, ints, idents/keywords, operators, newlines, eof | token-stream unit tests + `--emit-tokens` golden | — |
| `v1_fast` *(optional)* | tighter inner loop (avoid re-scanning, fewer allocations); measure lexer throughput (MB/s) | same tokens | beats v0 MB/s |

## Workflow

```bash
make explainer C=phase1-minimal/01-lexer     # read the lesson
# implement lexer.ml : next (in this directory)
make lab C=phase1-minimal/01-lexer           # run this concept's tests
dune exec swiftml -- --emit-tokens tests/programs/arith.swift
```

## Definition of done

`--emit-tokens` produces the right token stream for the Phase-1 corpus (the cram test in
`tests/` is green after `dune promote` records your output), source positions are tracked, and
comments + newlines are handled exactly. Then freeze `lexer.ml` into `solution/`.

Key Swift-specific things to get right (peek at the oracle): newlines are **significant** tokens
(Swift terminates statements at line breaks), block comments `/* */` **nest**, and identifiers
follow Swift's rules (letter/`_` then letters/digits/`_`).
