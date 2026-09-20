Every diagnostic lands on the OFFENDING token — the one that was found, not the one that
was hoped for. The wording is yours; these cases pin the position, because a message at
the wrong column is wrong however well it reads, and nothing else here would notice.

`let b = *` blames the `*` at column 9: that is the token that cannot begin an expression.

  $ printf 'let b = *\n' > p1.swift
  $ ./lab.exe --emit-ast p1.swift 2>&1 >/dev/null | head -1
  1:9: error: expected expression

`let = 5` blames the `=` at column 5, where an identifier should have been — swiftc agrees
to the column, though it says `expected pattern`, naming a construct this subset lacks.

  $ printf 'let = 5\n' > p2.swift
  $ ./lab.exe --emit-ast p2.swift 2>&1 >/dev/null | head -1
  1:5: error: expected identifier

`print((1 + 2)` blames the newline at column 14 — the token `expect` found where it wanted
`)`. swiftc reports this one at `2:1` instead: it scans to end of input before giving up.

  $ printf 'print((1 + 2)\n' > p3.swift
  $ ./lab.exe --emit-ast p3.swift 2>&1 >/dev/null | head -1
  1:14: error: expected ')'

`let a = 1 2` blames the `2` at column 11 — the token that should have been a newline.
swiftc reports column 10, the gap after `1`, because its message asks for a `;` to be
inserted there. Ours names what it found; both reject the program.

  $ printf 'let a = 1 2\n' > p4.swift
  $ ./lab.exe --emit-ast p4.swift 2>&1 >/dev/null | head -1
  1:11: error: expected newline or end of statement
