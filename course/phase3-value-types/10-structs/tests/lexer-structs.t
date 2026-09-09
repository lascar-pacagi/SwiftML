TODO(10a) lexical surface — `struct` becomes a keyword, a lone `.` becomes member-access
punctuation without breaking `..<`, and `;` becomes the same separator token as a newline.
`--emit-tokens` stops before the parser.

`struct` is a keyword while the following type name remains an identifier.

  $ printf 'struct Point {}\n' > keyword.swift
  $ ./lab.exe --emit-tokens keyword.swift
  struct
  ident(Point)
  {
  }
  newline
  eof

A lone dot is `Dot`, while the existing half-open-range token still consumes all three bytes.

  $ printf 'p.x\n0 ..< 2\n' > dots.swift
  $ ./lab.exe --emit-tokens dots.swift
  ident(p)
  .
  ident(x)
  newline
  int(0)
  ..<
  int(2)
  newline
  eof

A semicolon is a statement separator, represented by `Newline` so the parser has one rule.

  $ printf 'let x = 1; let y = 2\n' > semi.swift
  $ ./lab.exe --emit-tokens semi.swift
  let
  ident(x)
  =
  int(1)
  newline
  let
  ident(y)
  =
  int(2)
  newline
  eof
