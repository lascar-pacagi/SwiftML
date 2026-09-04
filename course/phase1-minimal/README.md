# Phase 1 — A minimal compiled language

The first real vertical slice: a **complete compiler** for integer arithmetic you can print.
By the end, every program in the Phase-1 corpus compiles to a native executable whose output
matches `swiftc` exactly (**Milestone M1**).

**The subset:** `Int` literals & arithmetic (`+ - * / %`, precedence, parentheses, unary `-`),
`let`/`var` bindings and references, `var` reassignment, `print(_:)`, top-level statements, and
`//` / `/* */` comments.

**How it's built:** each concept directory is **one self-contained stage** — the source file(s)
you edit live right there, alongside that stage's tests and a `solution/` answer key. Each stage is
its own small dune library that depends on the previous one, and the `swiftml` binary
(`phase1-minimal/bin/`) is assembled from all four. That's the "built step by step" structure: the
parser library depends on the lexer library, sema on parser, codegen on sema.

```
source ──Lexer──► tokens ──Parser──► AST ──Sema──► (checked) AST ──IRGen──► LLVM IR ──clang──► exe
   01-lexer/             02-parser/         03-sema/              04-codegen/        bin/ (swiftml)
 token.ml diagnostics.ml  ast.ml             sema.ml            irgen.ml driver.ml   main.ml
 lexer.ml ◄── you edit    parser.ml ◄edit     ◄── you edit       ◄── you edit
```

| Concept (the files live here) | You implement | Done when |
|---|---|---|
| [`01-lexer/`](01-lexer/) — `token.ml` `diagnostics.ml` `lexer.ml` | `lexer.ml : next` (scanning DFA) | the token-stream files pass; `oracle.t` agrees with swiftc |
| [`02-parser/`](02-parser/) — `ast.ml` `parser.ml` | `parser.ml : parse_expr_bp / parse_stmt / parse_program` | `parser-expr/-stmt/-program.t` pass; syntax verdicts match swiftc |
| [`03-sema/`](03-sema/) — `sema.ml` | `sema.ml : check` — scope + trivial type checking | ill-typed programs rejected like swiftc, message and column |
| [`04-codegen/`](04-codegen/) — `irgen.ml` `driver.ml` | `irgen.ml : emit_llvm` | programs **build and run**, byte-identical to swiftc — **M1** |

Work them in order — each builds on the previous stage's output. Read each concept's `README.md`
and `explainer.qmd`, fill the `TODO`s in that directory's source file, and turn `make lab` green:
one `.t` file per hole, so a finished hole shows up by name, and every concept's `oracle.t` puts
its corpus to `swiftc` on every run (accept/reject in 01–03, build-and-run in 04).

**Design oracle for the whole phase:** `../../swift/lib/Parse/{Lexer,Parser,ParseExpr}.cpp`,
`../../swift/lib/Sema/`, `../../swift/lib/IRGen/`.
