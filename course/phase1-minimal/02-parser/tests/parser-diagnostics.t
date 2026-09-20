Every diagnostic lands on the OFFENDING token — the one that was found, not the one that was
hoped for — and says what §2's table says it says. Three are asserted in full. The fourth,
the prefix error, is asserted by POSITION only (`cut` keeps the `line:col`): §6's first
exercise rewrites its text to name the token it found, and a test that forbade that would
forbid the exercise.

`let b = *` blames the `*` at column 9: the token that cannot begin an expression. Position
only here — see above.

  $ printf 'let b = *\n' > p1.swift
  $ ./lab.exe --emit-ast p1.swift 2>&1 >/dev/null | head -1 | cut -d: -f1,2
  1:9

`let = 5` blames the `=` at column 5, where the name should have been. The message names the
binding form, so `var` gets its own: `parse_ident`'s description parameter exists for that.

  $ printf 'let = 5\n' > p2.swift
  $ ./lab.exe --emit-ast p2.swift 2>&1 >/dev/null | head -1
  1:5: error: expected a constant name
  $ printf 'var = 5\n' > p2b.swift
  $ ./lab.exe --emit-ast p2b.swift 2>&1 >/dev/null | head -1
  1:5: error: expected a variable name

`let a 5` is missing its `=`. swiftc never reports this — `let a: Int` is a complete declaration
in Swift, so it reads `let a` as finished and blames `5` for being a second statement.

  $ printf 'let a 5\n' > p2c.swift
  $ ./lab.exe --emit-ast p2c.swift 2>&1 >/dev/null | head -1
  1:7: error: expected '='

`print((1 + 2)` blames the newline at column 14 — the token `expect` found where it wanted
`)`. swiftc reports `2:1` instead: it scans to end of input before giving up.

  $ printf 'print((1 + 2)\n' > p3.swift
  $ ./lab.exe --emit-ast p3.swift 2>&1 >/dev/null | head -1
  1:14: error: expected ')'

`let a = 1 2` blames the `2` at column 11 — the token that should have been a newline.
swiftc reports column 10, the gap after `1`, because its message asks for a `;` to be
inserted there. Ours names what it found; both reject the program.

  $ printf 'let a = 1 2\n' > p4.swift
  $ ./lab.exe --emit-ast p4.swift 2>&1 >/dev/null | head -1
  1:11: error: consecutive statements on a line must be separated by a newline
