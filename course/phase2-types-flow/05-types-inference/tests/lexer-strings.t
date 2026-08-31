The string scanner on its own, through `--emit-tokens` (the driver bails right after lexing).
Nothing here needs the parser, sema, or even the operator hole: the cases use `print("...")`
rather than `let s = "..."`, so `=` never appears. RED until `scan_string` is written.

`print("\1")` reports a bad escape at the `1`, after the backslash.
That is `diag::lex_invalid_escape`, and swiftc puts its caret there too, at column 9:

  $ printf 'print("\\1")\n' > e1.swift
  $ ./lab.exe --emit-tokens e1.swift 2>&1; echo "exit=$?"
  1:9: error: invalid escape sequence in literal
  exit=1

`print("oops` reports an unterminated literal once, on the opening quote.
That is `diag::lex_unterminated_string`; swiftc's caret is on the quote too, at column 7. A
loop that errors on the way out *and* again after it will print the line twice:

  $ printf 'print("oops\n' > e2.swift
  $ ./lab.exe --emit-tokens e2.swift 2>&1; echo "exit=$?"
  1:7: error: unterminated string literal
  exit=1

`"a\nb\tc\"d\\e"` decodes to real characters, no backslashes left.
The token carries one byte each — no backslashes and no stray letters left in the payload:

  $ printf 'print("a\\nb\\tc\\"d\\\\e")\n' > e3.swift
  $ ./lab.exe --emit-tokens e3.swift
  ident(print)
  (
  string("a\nb\tc\"d\\e")
  )
  newline
  eof

`print("abc\1` reports BOTH problems: the bad escape and the missing quote.
Reporting the escape doesn't stop the scan — that is what "recover" means — so the run then hits
a second, independent failure. swiftc prints the same two, in the same order:

  $ printf 'print("abc\\1\n' > e4.swift
  $ ./lab.exe --emit-tokens e4.swift 2>&1; echo "exit=$?"
  1:12: error: invalid escape sequence in literal
  1:7: error: unterminated string literal
  exit=1

`print("")` is a valid empty string, not an unterminated one.
The closing quote is found immediately, so the token carries an empty payload:

  $ printf 'print("")\n' > e5.swift
  $ ./lab.exe --emit-tokens e5.swift
  ident(print)
  (
  string("")
  )
  newline
  eof

`"a+b // not a comment"` is one token — no operators, no comments inside.
Once the scanner is inside a literal, every byte up to the closing quote is content; `//` and
`/*` are not trivia there, and `+` is not an operator:

  $ printf 'print("a+b // not a comment /* nor this */")\n' > e6.swift
  $ ./lab.exe --emit-tokens e6.swift
  ident(print)
  (
  string("a+b // not a comment /* nor this */")
  )
  newline
  eof

`"she said \"hi\""` — an escaped quote does not end the literal.
The `\"` is consumed by the escape branch, so the scan continues past it and the payload keeps a
real quote character:

  $ printf 'print("she said \\"hi\\"")\n' > e7.swift
  $ ./lab.exe --emit-tokens e7.swift
  ident(print)
  (
  string("she said \"hi\"")
  )
  newline
  eof
