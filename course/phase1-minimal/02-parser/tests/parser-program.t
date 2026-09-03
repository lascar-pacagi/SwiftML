Whole programs, through `./lab.exe --emit-ast` — the same output as `swiftml --emit-ast`, built
from this directory's parser. Needs `TODO(02c)` on top of 02a and 02b. RED until all three are
written.

A program is its statements in source order, one per line.

  $ printf 'let a = 6\nvar c = a + 7\nc = c * 2\nprint(c)\n' > a.swift
  $ ./lab.exe --emit-ast a.swift
  (let a 6)
  (var c (+ a 7))
  (= c (* c 2))
  (print c)

Blank lines and a comment-only line are separators, not statements.
The lexer emits a `newline` for each of them; `parse_program` has to skip the empty ones:

  $ printf '\n\nlet a = 1\n\n// just a comment\n\nprint(a)\n' > b.swift
  $ ./lab.exe --emit-ast b.swift
  (let a 1)
  (print a)

A file with no trailing newline still ends the last statement.

  $ printf 'let a = 1\nprint(a)' > c.swift
  $ ./lab.exe --emit-ast c.swift
  (let a 1)
  (print a)

`print(a) print(a)` on one line is an error: only a newline ends a statement.
`print(a) print(a)` is legal in no version of Swift (it wants a `;` or a line break):

  $ printf 'let a = 1\nprint(a) print(a)\n' > d.swift
  $ ./lab.exe --emit-ast d.swift 2>&1 >/dev/null | grep -c 'error:'
  1
  $ ./lab.exe --emit-ast d.swift >/dev/null 2>&1; echo "exit=$?"
  exit=1

Two bad lines yield two diagnostics: the parser recovers and keeps going.
The second and fourth lines are broken; both are reported, and the exit code is 1:

  $ printf 'let a = 1\nlet b = *\nprint(a)\nlet = 3\n' > e.swift
  $ ./lab.exe --emit-ast e.swift 2>&1 >/dev/null | grep -c 'error:'
  2
  $ ./lab.exe --emit-ast e.swift >/dev/null 2>&1; echo "exit=$?"
  exit=1
