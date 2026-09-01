The parser's literal prefixes, through `--emit-ast`. Needs the lexer holes (the tokens have to
exist first) plus the `TODO(05)` prefix arms in `parse_expr_bp`; it does not touch sema.

`true`, `"hi"` and `3.14` become Bool/String/Double AST nodes.
The tokens already arrive from the lexer; this is the prefix `match` turning each one into its
`Ast` node, mirroring the given `Int_lit` arm — advance, read the payload, keep the span:

  $ printf 'let b = true\nlet s = "hi"\nlet f = 3.14\n' > p1.swift
  $ ./lab.exe --emit-ast p1.swift
  (let b true)
  (let s "hi")
  (let f 3.14)
