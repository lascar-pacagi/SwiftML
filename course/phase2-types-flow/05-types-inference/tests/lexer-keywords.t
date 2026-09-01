Keyword recognition, through `--emit-tokens`. Nothing here needs the parser or sema. Note where
this hole lives: NOT in lexer.ml, which scans an identifier and hands the spelling to
`Token.keyword_or_ident`. RED until that table's `TODO(05)` arms are filled.

`print(true)` and `print(false)` lex as keywords, not identifiers.
Swift's Bool literals are keywords — a program cannot rebind `true` — so they get their own
token kinds rather than arriving as `ident(true)`:

  $ printf 'print(true)\nprint(false)\n' > k1.swift
  $ ./lab.exe --emit-tokens k1.swift | grep -E '^(true|false|ident)'
  ident(print)
  true
  ident(print)
  false

`truelle` and `falsette` stay identifiers: a keyword matches the WHOLE lexeme.
The scanner reads the longest identifier first and only then asks whether that exact spelling is
a keyword; matching a prefix instead would make `truely` lex as `true` followed by `ly`:

  $ printf 'print(truelle)\nprint(falsette, trueish)\n' > k2.swift
  $ ./lab.exe --emit-tokens k2.swift | grep -E '^ident' | grep -v print
  ident(truelle)
  ident(falsette)
  ident(trueish)

`let` and `var` still work — the Phase-1 arms are given, you add two more:

  $ printf 'let x\nvar y\n' > k3.swift
  $ ./lab.exe --emit-tokens k3.swift | grep -E '^(let|var)'
  let
  var

`letx`, `variable`, `true1` and `_true` are identifiers too — same rule, other keywords.
`variable` is the one that bites: a scanner that tested prefixes would lex it as `var` followed
by `iable`. Digits and `_` are identifier characters after the first, so `true1` and `_true` are
single identifiers as well:

  $ printf 'print(letx, variable)\nprint(true1, _true)\n' > k4.swift
  $ ./lab.exe --emit-tokens k4.swift | grep -E '^ident' | grep -v print
  ident(letx)
  ident(variable)
  ident(true1)
  ident(_true)

`as` is a keyword too, and `ascending` is not.
The coercion `e as T` needs `as` to arrive as its own kind — otherwise the parser sees an
identifier and the expression ends early. Same whole-lexeme rule as `true`:

  $ printf 'print(1 as Double)\n' > k5.swift
  $ ./lab.exe --emit-tokens k5.swift | grep -E '^(as|int)'
  int(1)
  as

  $ printf 'print(ascending, classy)\n' > k6.swift
  $ ./lab.exe --emit-tokens k6.swift | grep -E '^ident' | grep -v print
  ident(ascending)
  ident(classy)
