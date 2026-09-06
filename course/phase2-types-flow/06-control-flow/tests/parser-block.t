`parse_block` on its own, through `--emit-block`: the file IS a block, braces and all, so this
file goes green with the first `TODO(06)` body alone — before `parse_if` or any loop exists. A
block dumps as its statements in one pair of parentheses.

Every command runs under `timeout 5`, because the shape of this hole is a loop: a loop with no
arm that stops at `}` never terminates, and a hung test would hang `make lab` itself. A timed-out
run prints nothing and exits 124, so the report shows the case failing with an empty output
instead.

A block holds its statements in order:

  $ printf '{\n  let a = 1\n  print(a)\n}\n' > b1.swift
  $ timeout 5 ./lab.exe --emit-block b1.swift
  ((let a 1) (print a))

An empty block is an empty list, and so is a block of nothing but blank lines:

  $ printf '{\n}\n' > b2.swift
  $ timeout 5 ./lab.exe --emit-block b2.swift
  ()
  $ printf '{\n\n\n}\n' > b3.swift
  $ timeout 5 ./lab.exe --emit-block b3.swift
  ()

Blank lines around and between the statements are skipped, however many:

  $ printf '{\n\n  let a = 1\n\n\n  print(a)\n\n}\n' > b4.swift
  $ timeout 5 ./lab.exe --emit-block b4.swift
  ((let a 1) (print a))

A one-statement block fits on one line — the `}` ends the statement, so no newline is needed:

  $ printf '{ print(1) }\n' > b5.swift
  $ timeout 5 ./lab.exe --emit-block b5.swift
  ((print 1))

Two statements on one line are an error: a newline SEPARATES them, as at top level.
`{ print(1) print(2) }` is refused by swiftc too (*consecutive statements on a line…*):

  $ printf '{\n  print(1) print(2)\n}\n' > b6.swift
  $ timeout 5 ./lab.exe --emit-block b6.swift; echo "exit=$?"
  2:12: error: expected newline or end of statement
  exit=1

A block that runs off the end of the file is "expected '}'", at the end:

  $ printf '{\n  print(1)\n' > b7.swift
  $ timeout 5 ./lab.exe --emit-block b7.swift; echo "exit=$?"
  3:1: error: expected '}'
  exit=1

A block whose statements are every given form — binding, reassignment, bare expression:

  $ printf '{\n  let a = 1\n  var b = 2\n  b = a + b\n  print(b)\n  b\n}\n' > b8.swift
  $ timeout 5 ./lab.exe --emit-block b8.swift
  ((let a 1) (var b 2) (= b (+ a b)) (print b) b)

The `}` may sit on the same line as the last statement of a multi-statement block:

  $ printf '{\n  let a = 1\n  print(a) }\n' > b9.swift
  $ timeout 5 ./lab.exe --emit-block b9.swift
  ((let a 1) (print a))

A missing `{` is reported at the token that is there, and nothing is parsed as a block:

  $ printf 'print(1)\n' > b10.swift
  $ timeout 5 ./lab.exe --emit-block b10.swift; echo "exit=$?"
  1:1: error: expected '{'
  2:1: error: expected '}'
  exit=1

A statement that is itself broken is reported inside the block, once:

  $ printf '{\n  let = 1\n}\n' > b11.swift
  $ timeout 5 ./lab.exe --emit-block b11.swift; echo "exit=$?"
  2:7: error: expected identifier
  exit=1
