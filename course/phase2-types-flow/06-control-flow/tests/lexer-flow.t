The five new tokens, through `--emit-tokens` (the driver bails right after lexing, so nothing
downstream is involved). Needs the `TODO(06)` arm in the operator `match` of `lexer.ml`.

`{` and `}` are single-character tokens, each on its own:

  $ printf '{ }\n' > b.swift
  $ timeout 5 ./lab.exe --emit-tokens b.swift
  {
  }
  newline
  eof

`&&` and `||` are one token each — maximal munch, like `==`:

  $ printf 'true && false || true\n' > l.swift
  $ timeout 5 ./lab.exe --emit-tokens l.swift
  true
  &&
  false
  ||
  true
  newline
  eof

`..<` is one token, and `0..<n` needs no spaces around it:

  $ printf '0 ..< 3\n0..<n\n' > r.swift
  $ timeout 5 ./lab.exe --emit-tokens r.swift
  int(0)
  ..<
  int(3)
  newline
  int(0)
  ..<
  ident(n)
  newline
  eof

A lone `&` is "expected '&' after '&'", at the `&`, and lexing continues — exit 1, one error:

  $ printf 'true & false\n' > e1.swift
  $ timeout 5 ./lab.exe --emit-tokens e1.swift; echo "exit=$?"
  1:6: error: expected '&' after '&'
  exit=1

A lone `|` is "expected '|' after '|'", the same shape:

  $ printf 'true | false\n' > e2.swift
  $ timeout 5 ./lab.exe --emit-tokens e2.swift; echo "exit=$?"
  1:6: error: expected '|' after '|'
  exit=1

A `.` that does not start `..<` is "unexpected character '.'", once per stray dot:

  $ printf '0 .. 3\n' > e3.swift
  $ timeout 5 ./lab.exe --emit-tokens e3.swift; echo "exit=$?"
  1:3: error: unexpected character '.'
  1:4: error: unexpected character '.'
  exit=1

`&&` and `||` are maximal munch even when they meet other operators, and `..<` needs no spaces:

  $ printf 'a&&b||c\nx<..<y\n' > m1.swift
  $ timeout 5 ./lab.exe --emit-tokens m1.swift
  ident(a)
  &&
  ident(b)
  ||
  ident(c)
  newline
  ident(x)
  <
  ..<
  ident(y)
  newline
  eof

`{` and `}` are their own tokens against any neighbour — `if x{y=1}` needs no spaces at all:

  $ printf 'if x{y=1}\n' > m2.swift
  $ timeout 5 ./lab.exe --emit-tokens m2.swift
  if
  ident(x)
  {
  ident(y)
  =
  int(1)
  }
  newline
  eof

Two stray `&`s report twice — the lexer recovers and keeps scanning after each:

  $ printf 'a & b & c\n' > m3.swift
  $ timeout 5 ./lab.exe --emit-tokens m3.swift; echo "exit=$?"
  1:3: error: expected '&' after '&'
  1:7: error: expected '&' after '&'
  exit=1

`&&&` is one `&&` followed by a lone `&`, which reports:

  $ printf 'a &&& b\n' > m4.swift
  $ timeout 5 ./lab.exe --emit-tokens m4.swift; echo "exit=$?"
  1:5: error: expected '&' after '&'
  exit=1

`..` and `...` both report the stray dots and keep going, one message per dot:

  $ printf '0 ... 3\n' > m5.swift
  $ timeout 5 ./lab.exe --emit-tokens m5.swift; echo "exit=$?"
  1:3: error: unexpected character '.'
  1:4: error: unexpected character '.'
  1:5: error: unexpected character '.'
  exit=1
