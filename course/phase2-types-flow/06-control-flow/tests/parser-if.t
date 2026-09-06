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

The condition is a full expression, including the new logical operators, and needs no parentheses:

  $ printf 'if a < b && c || d {\n  print(1)\n}\n' > i6.swift
  $ timeout 5 ./lab.exe --emit-if i6.swift
  (if (|| (&& (< a b) c) d) ((print 1)))

Both blocks may be empty:

  $ printf 'if c {\n} else {\n}\n' > i7.swift
  $ timeout 5 ./lab.exe --emit-if i7.swift
  (if c () ())

An `else if` chain nests as deeply as it is written — three levels here:

  $ printf 'if a {\n  print(1)\n} else if b {\n  print(2)\n} else if c {\n  print(3)\n} else {\n  print(4)\n}\n' > i8.swift
  $ timeout 5 ./lab.exe --emit-if i8.swift
  (if a ((print 1)) ((if b ((print 2)) ((if c ((print 3)) ((print 4)))))))

`else` may start the next line, which swiftc accepts too.
`parse_if` looks past the newlines after the then-block for the keyword, and puts them back when
what follows is not an `else` — they are the separator the caller is about to need:

  $ printf 'if c {\n  print(1)\n}\nelse {\n  print(2)\n}\n' > i9.swift
  $ timeout 5 ./lab.exe --emit-if i9.swift; echo "exit=$?"
  (if c ((print 1)) ((print 2)))
  exit=0

A missing `{` after `else` is reported there:

  $ printf 'if c {\n  print(1)\n} else print(2)\n' > e2.swift
  $ timeout 5 ./lab.exe --emit-if e2.swift; echo "exit=$?"
  3:8: error: expected '{'
  4:1: error: expected '}'
  exit=1

A blank line before `else` is fine too, and so is a comment-only line:

  $ printf 'if c {\n  print(1)\n}\n\n// here\nelse {\n  print(2)\n}\n' > i10.swift
  $ timeout 5 ./lab.exe --emit-if i10.swift
  (if c ((print 1)) ((print 2)))

However many lines separate them: `nl` is one-or-more newlines, so the skip is a loop, not one
step. swiftc accepts this too:

  $ printf 'if c {\n  print(1)\n}\n\n\n\nelse {\n  print(2)\n}\n' > i12.swift
  $ timeout 5 ./lab.exe --emit-if i12.swift
  (if c ((print 1)) ((print 2)))

And the put-back is a loop as well — four blank lines after an `if` with no `else` are still the
caller's separator, not part of the statement:

  $ printf 'if c {\n  print(1)\n}\n\n\n\nprint(2)\n' > i13.swift
  $ timeout 5 ./lab.exe --emit-ast i13.swift
  (if c ((print 1)))
  (print 2)

But an `if` with no `else` still ends at its `}`: the newlines after it are left for the caller,
so the statement that follows parses as its own:

  $ printf 'if c {\n  print(1)\n}\nprint(2)\n' > i11.swift
  $ timeout 5 ./lab.exe --emit-ast i11.swift
  (if c ((print 1)))
  (print 2)
