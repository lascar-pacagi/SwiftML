The number scanner on its own, through `--emit-tokens` (the driver bails right after lexing).
Nothing here needs the parser, sema, or the other lexer holes — the programs are written
`print(...)`, so no `=` appears. RED until the `TODO(05)` fractional-part hole is filled.

`print(42)` is an `int` — the Phase-1 path still works.
A digit run with no `.` after it is an integer literal; `0` and a long run are the same case:

  $ printf 'print(42)\nprint(0)\nprint(1234567890)\n' > n0.swift
  $ ./lab.exe --emit-tokens n0.swift | grep -E '^int'
  int(42)
  int(0)
  int(1234567890)

`print(3.14)` lexes as one `float`, not `int` `.` `int`.
The scan reads a digit run, sees a `.` followed by another digit, and keeps going — one token
carrying the value, produced with `float_of_string` over the whole lexeme:

  $ printf 'print(3.14)\n' > n1.swift
  $ ./lab.exe --emit-tokens n1.swift
  ident(print)
  (
  float(3.14)
  )
  newline
  eof

The fractional part is what makes a Float: `1` is an int, `1.5` is a float.
Same digit run, different token kind, decided by what follows it:

  $ printf 'print(1)\nprint(1.5)\n' > n2.swift
  $ ./lab.exe --emit-tokens n2.swift | grep -E '^(int|float)'
  int(1)
  float(1.5)

`print(2.0)` is a float whose *printer* drops the trailing zero.
The token holds 2.0; `Token.string_of_kind` formats floats with `%g`, so the token stream reads
`float(2)`. That is the dump, not the value — don't "fix" the scanner over it:

  $ printf 'print(2.0)\n' > n3.swift
  $ ./lab.exe --emit-tokens n3.swift | grep float
  float(2)

`print(1.)` and `print(.5)` are not literals — the `.` is left over.
Swift requires digits on both sides, and `.` is not a token in this subset (it arrives with
member access in concept 10), so the leftover dot is an invalid character. swiftc rejects both
too, with its own wording: "expected member name following '.'" and "'.5' is not a valid
floating point literal; it must be written '0.5'":

  $ printf 'print(1.)\n' > n4.swift
  $ ./lab.exe --emit-tokens n4.swift 2>&1; echo "exit=$?"
  1:8: error: invalid character in source file
  exit=1

  $ printf 'print(.5)\n' > n5.swift
  $ ./lab.exe --emit-tokens n5.swift 2>&1; echo "exit=$?"
  1:7: error: invalid character in source file
  exit=1
