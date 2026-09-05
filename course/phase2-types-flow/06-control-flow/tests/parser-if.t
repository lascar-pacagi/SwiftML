`if` and blocks, through `--emit-ast`. Needs `parse_block` and `parse_if` (the two `TODO(06)`
holes at the top of the statement parser). A block dumps as a parenthesised statement list.

`if c { print(1) }` is an `if` with a one-statement block and no else:

  $ printf 'let c = true\nif c {\n  print(1)\n}\n' > i1.swift
  $ ./lab.exe --emit-ast i1.swift
  (let c true)
  (if c ((print 1)))

`if … { } else { }` carries both blocks:

  $ printf 'let c = true\nif c {\n  print(1)\n} else {\n  print(2)\n}\n' > i2.swift
  $ ./lab.exe --emit-ast i2.swift
  (let c true)
  (if c ((print 1)) ((print 2)))

`else if` is an `if` nested as the sole statement of the else block — no third form:

  $ printf 'let n = 2\nif n == 1 {\n  print(1)\n} else if n == 2 {\n  print(2)\n} else {\n  print(0)\n}\n' > i3.swift
  $ ./lab.exe --emit-ast i3.swift
  (let n 2)
  (if (== n 1) ((print 1)) ((if (== n 2) ((print 2)) ((print 0)))))

A block holds several statements, in order, blank lines skipped:

  $ printf 'if true {\n  let a = 1\n\n  let b = a + 1\n  print(b)\n}\n' > i4.swift
  $ ./lab.exe --emit-ast i4.swift
  (if true ((let a 1) (let b (+ a 1)) (print b)))

An `if` inside a block nests:

  $ printf 'if true {\n  if false {\n    print(0)\n  }\n  print(1)\n}\n' > i5.swift
  $ ./lab.exe --emit-ast i5.swift
  (if true ((if false ((print 0))) (print 1)))

A missing `{` after the condition is "expected '{'", reported at the token found there:

  $ printf 'if true\n  print(1)\n}\n' > e1.swift
  $ ./lab.exe --emit-ast e1.swift; echo "exit=$?"
  1:8: error: expected '{'
  exit=1
