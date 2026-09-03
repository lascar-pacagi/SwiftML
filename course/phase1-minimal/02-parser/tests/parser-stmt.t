One statement at a time, through `./lab.exe --emit-stmt`, which calls `parse_stmt` once — so this
needs `TODO(02b)` (plus 02a, since statements contain expressions) but not the program loop.
RED until 02b is written.

`let a = 6` is a binding; `var c = a + 7` is a mutable one.
Both are one statement shape with a flag; the dump keeps the keyword you wrote:

  $ printf 'let a = 6\n' > a.swift
  $ ./lab.exe --emit-stmt a.swift
  (let a 6)

  $ printf 'var c = a + 7\n' > b.swift
  $ ./lab.exe --emit-stmt b.swift
  (var c (+ a 7))

`c = c * 2` is a reassignment, a statement of its own.
It starts with an identifier, like an expression statement does, so `parse_stmt` needs ONE
token of lookahead past the name to see the `=` and choose:

  $ printf 'c = c * 2\n' > c.swift
  $ ./lab.exe --emit-stmt c.swift
  (= c (* c 2))

`print(a)` is an expression statement: no keyword, no `=`.

  $ printf 'print(a)\n' > d.swift
  $ ./lab.exe --emit-stmt d.swift
  (print a)

`let = 5` — a binding with no name — is reported, exit 1.
The shape of the diagnostic is asserted, not the wording (§6 exercise 1):

  $ printf 'let = 5\n' > bad.swift
  $ ./lab.exe --emit-stmt bad.swift 2>&1 >/dev/null | grep -c 'error:'
  1
  $ ./lab.exe --emit-stmt bad.swift >/dev/null 2>&1; echo "exit=$?"
  exit=1
