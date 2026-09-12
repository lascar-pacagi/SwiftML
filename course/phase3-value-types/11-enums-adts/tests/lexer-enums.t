TODO(11a) enum keywords — `enum` and `case` become keywords while longer words remain
identifiers. `--emit-tokens` stops before the parser.

The two declaration words are keywords.

  $ printf 'enum Direction { case north }\n' > keywords.swift
  $ ./lab.exe --emit-tokens keywords.swift
  enum
  ident(Direction)
  {
  case
  ident(north)
  }
  newline
  eof

Keyword matching is exact, so nearby identifiers keep their full spelling.

  $ printf 'enumerated suitcase enumValue caseValue\n' > identifiers.swift
  $ ./lab.exe --emit-tokens identifiers.swift
  ident(enumerated)
  ident(suitcase)
  ident(enumValue)
  ident(caseValue)
  newline
  eof
