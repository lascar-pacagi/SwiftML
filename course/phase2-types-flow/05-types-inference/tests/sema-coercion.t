The one coercion, through `--typecheck`. This is `TODO(05a)`'s rule — `is_int_literal` — seen from
outside: it decides, for every program below, whether the value may become a Double. Each case was
checked against `swiftc -typecheck`, and both compilers agree on all of them.

`let d: Double = 1 + 2` is accepted: an arithmetic tree of integer literals may flex.
The literal has no type of its own until something asks for one, so the annotation gets to choose
Double — Swift's `ExpressibleByIntegerLiteral`, narrowed here to the shapes we can recognise:

  $ printf 'let d: Double = 1 + 2\n' > y1.swift
  $ ./lab.exe --typecheck y1.swift >/dev/null 2>&1; echo "exit=$?"
  exit=0

`let d: Double = i` is rejected: an Int *variable* never flexes.
This is the asymmetry the predicate exists for — `i` already has a type, and Swift does not convert
between numeric types implicitly:

  $ printf 'let i = 1\nlet d: Double = i\n' > y2.swift
  $ ./lab.exe --typecheck y2.swift 2>&1; echo "exit=$?"
  2:17: error: cannot convert value of type 'Int' to specified type 'Double'
  exit=1

`-1` and `1 + 2 * 3` are still literals: the predicate recurses.
Unary minus and nested arithmetic keep every leaf a literal, so the whole tree may flex:

  $ printf 'let a: Double = -1\nlet b: Double = 1 + 2 * 3\nlet c: Double = 1 / 2\n' > y3.swift
  $ ./lab.exe --typecheck y3.swift >/dev/null 2>&1; echo "exit=$?"
  exit=0

One non-literal leaf is enough to stop it: `1 + i` is rejected.
The recursion is an AND over the operands, not an OR — a single typed variable anywhere in the tree
fixes the whole expression at Int:

  $ printf 'let i = 1\nlet d: Double = 1 + i\n' > y4.swift
  $ ./lab.exe --typecheck y4.swift 2>&1; echo "exit=$?"
  2:21: error: cannot convert value of type 'Int' to specified type 'Double'
  exit=1

The same rule applies on assignment, not just on `let`: `x = 3` where `x: Double`.
`check_stmt`'s Assign path checks the value against the variable's type, so the literal flexes
there too:

  $ printf 'var x: Double = 0\nx = 3\n' > y5.swift
  $ ./lab.exe --typecheck y5.swift >/dev/null 2>&1; echo "exit=$?"
  exit=0

`let d: Double = 1 % 2` is rejected — `%` is Int-only, in both compilers.
Flexing is not unconditional: the operator has to exist at the target type. swiftc rejects this one
too (there is no `%` on `Double`; Swift spells that `truncatingRemainder`):

  $ printf 'let d: Double = 1 %% 2\n' > y6.swift
  $ ./lab.exe --typecheck y6.swift 2>&1; echo "exit=$?"
  1:17: error: cannot convert value of type 'Int' to specified type 'Double'
  exit=1
