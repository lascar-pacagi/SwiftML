The operator half of the lexer, on its own, through `--emit-tokens`. Nothing here needs the
parser or sema — but it does need `scan_string`'s neighbours in the same `match`, so run it
after `lexer-strings.t`. RED until the `TODO(05)` operator hole is filled.

`a == b` lexes as one `==`, not two `=` — maximal munch.
`=`/`==` share a prefix, as do `<`/`<=` and `>`/`>=`; the longest lexeme wins:

  $ printf 'a == b\na = b\n' > m1.swift
  $ ./lab.exe --emit-tokens m1.swift
  ident(a)
  ==
  ident(b)
  newline
  ident(a)
  =
  ident(b)
  newline
  eof

`a<b a<=b a>b a>=b a!=b` lex with no spaces around them:

  $ printf 'a<b\na<=b\na>b\na>=b\na!=b\n' > m2.swift
  $ ./lab.exe --emit-tokens m2.swift | grep -v 'ident\|newline\|eof'
  <
  <=
  >
  >=
  !=

`let d: Double = 1` lexes the `:` as its own token:

  $ printf 'let d: Double = 1\n' > m3.swift
  $ ./lab.exe --emit-tokens m3.swift
  let
  ident(d)
  :
  ident(Double)
  =
  int(1)
  newline
  eof

`a ! b` reports "expected '=' after '!'" instead of a token.
Nothing uses it until concept 13 gives it a meaning (force-unwrap), so the lexer reports and
recovers. swiftc's lexer accepts `!` and complains later from the parser, so this wording is ours:

  $ printf 'a ! b\n' > m4.swift
  $ ./lab.exe --emit-tokens m4.swift 2>&1; echo "exit=$?"
  1:3: error: expected '=' after '!'
  exit=1
