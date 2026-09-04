The `return` statement, through `--emit-ast` (parse only — sema never runs, so a top-level
`return` is fine here). Needs the `Kw_return` arm of `parse_stmt`, the first `TODO(07)` in
`parser.ml`. A value dumps as `(return e)`, no value as `(return)`.

`return 1 + 2` carries the whole expression:

  $ printf 'return 1 + 2\n' > r1.swift
  $ ./lab.exe --emit-ast r1.swift
  (return (+ 1 2))

A bare `return` before a newline has no value:

  $ printf 'return\nprint(1)\n' > r2.swift
  $ ./lab.exe --emit-ast r2.swift
  (return)
  (print 1)

A bare `return` at end of input, with no newline after it, has no value:

  $ printf 'return' > r3.swift
  $ ./lab.exe --emit-ast r3.swift
  (return)

A bare `return` right before `}` ends the block: `if c { return }`:

  $ printf 'if c { return }\n' > r4.swift
  $ ./lab.exe --emit-ast r4.swift
  (if c ((return)))

`return x` inside a block is a statement like any other, in order with its neighbours:

  $ printf 'if c {\n  print(1)\n  return x\n}\n' > r5.swift
  $ ./lab.exe --emit-ast r5.swift
  (if c ((print 1) (return x)))

The value may be a call — `return fib(n - 1) + fib(n - 2)` is one expression:

  $ printf 'return fib(n - 1) + fib(n - 2)\n' > r6.swift
  $ ./lab.exe --emit-ast r6.swift
  (return (+ (fib (- n 1)) (fib (- n 2))))

Two statements on one line are still an error — `return 1 print(2)` stops at `print`:

  $ printf 'return 1 print(2)\n' > e1.swift
  $ ./lab.exe --emit-ast e1.swift; echo "exit=$?"
  1:10: error: expected newline or end of statement
  exit=1
