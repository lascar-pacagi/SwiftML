`parse_block` on its own, through `--emit-block`: the file IS a block, braces and all, so this
file goes green with the first `TODO(06)` body alone — before `parse_if` or any loop exists. A
block dumps as its statements in one pair of parentheses.

A block holds its statements in order:

  $ printf '{\n  let a = 1\n  print(a)\n}\n' > b1.swift
  $ ./lab.exe --emit-block b1.swift
  ((let a 1) (print a))

An empty block is an empty list, and so is a block of nothing but blank lines:

  $ printf '{\n}\n' > b2.swift
  $ ./lab.exe --emit-block b2.swift
  ()
  $ printf '{\n\n\n}\n' > b3.swift
  $ ./lab.exe --emit-block b3.swift
  ()

Blank lines around and between the statements are skipped, however many:

  $ printf '{\n\n  let a = 1\n\n\n  print(a)\n\n}\n' > b4.swift
  $ ./lab.exe --emit-block b4.swift
  ((let a 1) (print a))

A one-statement block fits on one line — the `}` ends the statement, so no newline is needed:

  $ printf '{ print(1) }\n' > b5.swift
  $ ./lab.exe --emit-block b5.swift
  ((print 1))

Two statements on one line are an error: a newline SEPARATES them, as at top level.
`{ print(1) print(2) }` is refused by swiftc too (*consecutive statements on a line…*):

  $ printf '{\n  print(1) print(2)\n}\n' > b6.swift
  $ ./lab.exe --emit-block b6.swift; echo "exit=$?"
  2:12: error: expected newline or end of statement
  exit=1

A block that runs off the end of the file is "expected '}'", at the end:

  $ printf '{\n  print(1)\n' > b7.swift
  $ ./lab.exe --emit-block b7.swift; echo "exit=$?"
  3:1: error: expected '}'
  exit=1
