`parse_if` on its own, through `--emit-if`: the file IS an if-statement, so this file goes green
with `parse_block` + `parse_if`, before `parse_stmt` learns to dispatch on the new keywords. Every
command runs under `timeout 5`, because an unterminated loop in either function would otherwise
hang the run.

`if c { … }` with no else is an `if` with one block:

  $ printf 'if c {\n  print(1)\n}\n' > i1.swift
  $ timeout 5 ./lab.exe --emit-if i1.swift
  (if c ((print 1)))

`if … { } else { }` carries both blocks:

  $ printf 'if c {\n  print(1)\n} else {\n  print(2)\n}\n' > i2.swift
  $ timeout 5 ./lab.exe --emit-if i2.swift
  (if c ((print 1)) ((print 2)))

`else if` is an `if` nested as the sole statement of the else block — no third form:

  $ printf 'if n == 1 {\n  print(1)\n} else if n == 2 {\n  print(2)\n} else {\n  print(0)\n}\n' > i3.swift
  $ timeout 5 ./lab.exe --emit-if i3.swift
  (if (== n 1) ((print 1)) ((if (== n 2) ((print 2)) ((print 0)))))

The blocks hold several statements, in order, blank lines skipped:

  $ printf 'if true {\n  let a = 1\n\n  let b = a + 1\n  print(b)\n}\n' > i4.swift
  $ timeout 5 ./lab.exe --emit-if i4.swift
  (if true ((let a 1) (let b (+ a 1)) (print b)))

A one-line `if` is legal — the `}` ends the statement inside it:

  $ printf 'if true { print(1) } else { print(2) }\n' > i5.swift
  $ timeout 5 ./lab.exe --emit-if i5.swift
  (if true ((print 1)) ((print 2)))

A missing `{` after the condition is "expected '{'", reported at the token found there:

  $ printf 'if true\n  print(1)\n}\n' > e1.swift
  $ timeout 5 ./lab.exe --emit-if e1.swift; echo "exit=$?"
  1:8: error: expected '{'
  exit=1
