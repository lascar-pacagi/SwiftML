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

Add a program here whenever a concept introduces new surface syntax, then assert parity in that
concept's `tests/`. Keep each program small and focused on the feature it names.
