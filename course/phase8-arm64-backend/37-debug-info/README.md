# 37 · Debug info — source locations & a DWARF line table

**Objective:** make a `swiftml`-built native binary **debuggable**. Thread source line numbers from
the AST all the way to the machine code, emit `.file`/`.loc` directives, and let the assembler turn
them into a real **DWARF line table** — an address↔line map, the section a debugger consults
first. This is the last piece of **M8-core**: a from-scratch native backend that is not just
correct and fast, but traceable back to source.

**You edit:** `isel.ml` — `TODO(37)`: `emit_loc`, which emits a `.loc` directive whenever the source
line changes. The line *threading* (SILGen stamps each SIL value with its statement's line; the SIL
carries a `lines` map; `clang -g` builds the DWARF) is given.

**Design oracle:** the DWARF debugging standard (the line-number program), LLVM's `MCStreamer`
`.loc`/`.file` directives, and Apple's debug-map model (DWARF in the `.o`, a map in the executable).

## What this concept adds
- **Line threading end-to-end.** SILGen sets a `cur_line` per statement (`Ast.stmt_line`) and stamps
  it onto every SIL value it emits; the SIL `func` carries a `lines : value → line` map.
- **`.loc` / `.file` emission.** isel emits `Arm64.Loc n` when the line changes; the printer renders
  `.file 1 "<source>"` once and `.loc 1 n 0` per change. `clang -g` assembles these into a DWARF
  line table.
- **A `-g` native build.** The `--native` build now passes `-g` and keeps the `.o` (macOS stores
  DWARF there and leaves a debug map in the executable, and `clang -g x.s -o exe` would delete the
  temporary object and lose the DWARF entirely).

## Done when
`make lab C=phase8-arm64-backend/37-debug-info` green: the asm carries a `.file` and one `.loc` per
statement line; the built `.o` has a **DWARF line table** mapping machine addresses to the right
source lines (verified with `dwarfdump --debug-line`); and programs still run and match `swiftc`
under both backends.

> **Scope (v0), stated plainly.** A **line table** only. `.debug_info` is EMPTY, so `lldb` has no
> compile-unit or subprogram DIE to bind a source breakpoint to: `breakpoint set --file … --line …`
> answers "no locations (pending)". The table is real and complete — `dwarfdump --debug-line` is the
> automated check — and it is what a debugger needs *first*, not all it needs. Emitting a minimal
> compile unit + subprogram DIE (exercise 2) is what makes the debugger work; variable locations,
> column accuracy, `.dSYM` and inlined frames follow. We also let `clang -g` build the DWARF from our
> directives rather than hand-encode the line-number program (that encoding is exercise 1).
