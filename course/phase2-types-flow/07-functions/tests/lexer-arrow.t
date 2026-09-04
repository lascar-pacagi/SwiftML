The `->` arrow, through `--emit-tokens` (the driver bails right after lexing, so nothing
downstream is involved). Needs the `TODO(07)` peek in the `'-'` arm of `lexer.ml`.

`-> Int` is one arrow token, then the identifier:

  $ printf -- '-> Int\n' > a.swift
  $ ./lab.exe --emit-tokens a.swift
  ->
  ident(Int)
  newline
  eof

`a -> b` and `a->b` both lex to an arrow — no space is needed on either side:

  $ printf 'a -> b\na->b\n' > b.swift
  $ ./lab.exe --emit-tokens b.swift
  ident(a)
  ->
  ident(b)
  newline
  ident(a)
  ->
  ident(b)
  newline
  eof

A `-` not followed by `>` is still minus: `a - b`, `-1`, and `a-b`:

  $ printf 'a - b\n-1\na-b\n' > c.swift
  $ ./lab.exe --emit-tokens c.swift
  ident(a)
  -
  ident(b)
  newline
  -
  int(1)
  newline
  ident(a)
  -
  ident(b)
  newline
  eof

`- >` with a space between is minus then greater-than, not an arrow:

  $ printf 'a - > b\n' > d.swift
  $ ./lab.exe --emit-tokens d.swift
  ident(a)
  -
  >
  ident(b)
  newline
  eof

`a->-b` is an arrow followed by a minus — the peek consumes exactly one `>`:

  $ printf 'a->-b\n' > e.swift
  $ ./lab.exe --emit-tokens e.swift
  ident(a)
  ->
  -
  ident(b)
  newline
  eof
