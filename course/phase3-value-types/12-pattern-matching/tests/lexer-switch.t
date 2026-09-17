TODO(12a) switch keywords — `switch` and `default` become keywords while longer words that
merely start the same way stay identifiers. `--emit-tokens` stops before the parser.

The two arm-introducing words are keywords.

  $ printf 'switch x { default: y }\n' > kw.swift
  $ ./lab.exe --emit-tokens kw.swift
  switch
  ident(x)
  {
  default
  :
  ident(y)
  }
  newline
  eof

Keyword matching is whole-word, so nearby identifiers keep their spelling.

  $ printf 'switchboard defaults switching\n' > ident.swift
  $ ./lab.exe --emit-tokens ident.swift
  ident(switchboard)
  ident(defaults)
  ident(switching)
  newline
  eof
