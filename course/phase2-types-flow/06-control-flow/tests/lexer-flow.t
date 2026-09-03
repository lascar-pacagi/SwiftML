The five new tokens, through `--emit-tokens` (the driver bails right after lexing, so nothing
downstream is involved). Needs the `TODO(06)` arm in the operator `match` of `lexer.ml`.

`{` and `}` are single-character tokens, each on its own:

  $ printf '{ }\n' > b.swift
  $ ./lab.exe --emit-tokens b.swift
  {
  }
  newline
  eof

`&&` and `||` are one token each — maximal munch, like `==`:

  $ printf 'true && false || true\n' > l.swift
  $ ./lab.exe --emit-tokens l.swift
  true
  &&
  false
  ||
  true
  newline
  eof

`..<` is one token, and `0..<n` needs no spaces around it:

  $ printf '0 ..< 3\n0..<n\n' > r.swift
  $ ./lab.exe --emit-tokens r.swift
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
  $ ./lab.exe --emit-tokens e1.swift; echo "exit=$?"
  1:6: error: expected '&' after '&'
  exit=1

A lone `|` is "expected '|' after '|'", the same shape:

  $ printf 'true | false\n' > e2.swift
  $ ./lab.exe --emit-tokens e2.swift; echo "exit=$?"
  1:6: error: expected '|' after '|'
  exit=1

A `.` that does not start `..<` is "unexpected character '.'", once per stray dot:

  $ printf '0 .. 3\n' > e3.swift
  $ ./lab.exe --emit-tokens e3.swift; echo "exit=$?"
  1:3: error: unexpected character '.'
  1:4: error: unexpected character '.'
  exit=1
