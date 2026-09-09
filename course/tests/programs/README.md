# tests/programs/ — the shared `.swift` corpus

Real Swift programs that must behave identically under `swiftml` and `swiftc`. The corpus grows
one phase at a time; every program here is expected to be within the *currently supported subset*.

Run one through the oracle:

```bash
make oracle F=tests/programs/arith.swift
```

| Program | Phase | Exercises |
|---|---|---|
| `arith.swift` | 1 | integer arithmetic, precedence, parens, unary minus, `print` |
| `vars.swift`  | 1 | `let`/`var`, variable references, reassignment |
| `arith2.swift` | 1 | division/remainder signedness, nested parens, longer expressions |
| `if.swift` | 2 (08) | the `if` diamond: with an else, without one, an else-if chain, and both arms returning |
| `while.swift` | 2 (08) | the loop header and its back edge; a condition false on entry; nesting |
| `for.swift` | 2 (08) | `for` desugared: slot, header, body, latch; the bound evaluated once; an empty range |
| `breakcontinue.swift` | 2 (08) | where each one branches — break to the exit, continue to the header or the LATCH — and which loop it targets in a nest |
| `shortcircuit.swift` | 2 (08) | `&&`/`||` as control flow: the right operand runs only on the deciding edge |
| `functions.swift` | 2 (09) | several signatures, calls between functions, nested calls, returned values, and a `Void` call |
| `controlflow.swift` | 2 (08) | the capstone: every construct of the section in one working program — functions, recursion, mutual recursion, if/else-if, while, for, break, continue, nested loops, short-circuit, an early `return`, Double |

## Reading the SIL

The concept-08 programs are here to be *looked at*, not only run. Its lab binary prints the SIL
without needing the rest of the phase:

```bash
L=_build/default/phase2-types-flow/08-sil-silgen/tests/lab.exe
$L --emit-sil       tests/programs/for.swift    # as SILGen emitted it
$L --emit-sil-canon tests/programs/for.swift    # normalised: see tests/canon.ml
```

Read `--emit-sil` first — the block ids are in the order your lowering created them, which is
itself informative. The canonical form is what the control-flow goldens compare, so a diff
between the two shows exactly which of your choices the tests are ignoring.

And the same program through the real thing, to compare shapes:

```bash
swiftc -emit-sil tests/programs/for.swift | less
```

Add a program here whenever a concept introduces new surface syntax, then assert parity in that
concept's `tests/`. Keep each program small and focused on the feature it names.
