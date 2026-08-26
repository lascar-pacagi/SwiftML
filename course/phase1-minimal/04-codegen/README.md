# 04 · codegen (AST → LLVM IR → native executable)

**Objective:** lower the checked AST to **LLVM IR** (as text), then let the driver hand that IR to
`clang` to produce a native arm64 executable. This closes the Phase-1 loop: `swiftml build
arith.swift` makes a real program whose output matches `swiftc`.

**Prerequisites:** 01–03 (you need a checked AST).

**You edit:** `irgen.ml : emit_llvm` (in this directory; and read the already-written `driver.ml`
here, which writes the `.ll` and invokes clang). This concept is the **codegen stage library**
(`swiftml_codegen`); the `swiftml` binary (`phase1-minimal/bin/`) is assembled from it plus the
three earlier stages.

**Design oracle:** `../../swift/lib/IRGen/` (`GenExpr.cpp`, `IRGenSIL.cpp`) and the
[LLVM Language Reference](https://llvm.org/docs/LangRef.html). Note: real swiftc lowers **SIL** to
LLVM IR; we lower the AST directly in Phase 1 and introduce SIL in Phase 2.

## What you build

One lowering, in four exported pieces — `slot_of`, `emit_expr`, `emit_stmt`, `emit_llvm` — each
tested on its own by `tests/test_irgen.ml`. The model is the straightforward one: an `alloca` per
`let`/`var`, `load`/`store` at every use, one register per subexpression, and **`make oracle`
parity** as the bar.

Two of §6's exercises make it emit less (skipping the slot for never-reassigned `let`s, folding
constant arithmetic); `tests/test_exercises.ml` checks them, and skips until you start.

## Workflow

```bash
make explainer C=phase1-minimal/04-codegen
make lab C=phase1-minimal/04-codegen          # compiles+runs sample programs
make oracle F=tests/programs/arith.swift      # behavioral parity vs swiftc
make oracle F=tests/programs/vars.swift
dune exec swiftml -- --emit-llvm tests/programs/arith.swift   # inspect the IR
```

## Definition of done — **this is Milestone M1**

`make oracle` says `OK` for every program in `tests/programs/` (identical stdout + exit code to
`swiftc`). Inspect `--emit-llvm` and confirm it's a valid, readable module. Freeze
`irgen.ml` into `solution/`.

**Parity gotchas to watch (see CLAUDE.md):** integer `print` formatting (Swift prints `Int` with no
decoration + a trailing newline), integer division/remainder semantics, and — once you add bigger
programs — Swift's **trap on overflow** at `-Onone`. For the Phase-1 corpus plain `add/sub/mul/sdiv/
srem i64` matches; note where you'll need overflow-checked intrinsics in Phase 2.
