TODO(11f) enum observation — `.rawValue` is limited to `: Int` enums, and equality is
available only when no case carries an associated value.

An Int raw-value enum exposes an Int through `.rawValue`.

  $ printf 'enum Direction: Int { case north, south }\nlet n: Int = Direction.south.rawValue\n' > raw.swift
  $ ./lab.exe --typecheck raw.swift

A plain enum has no `rawValue` member.

  $ printf 'enum Color { case red }\nprint(Color.red.rawValue)\n' > no-raw.swift
  $ ./lab.exe --typecheck no-raw.swift
  2:7: error: value of type 'Color' has no member 'rawValue'
  [1]

A payload-free enum is implicitly Equatable.

  $ printf 'enum Color { case red, green }\nprint(Color.red == Color.green)\n' > equal.swift
  $ ./lab.exe --typecheck equal.swift

An enum with associated values needs an Equatable conformance that this subset cannot synthesize.

  $ printf 'enum E { case value(Int); case empty }\nprint(E.value(1) == E.value(1))\n' > not-equal.swift
  $ ./lab.exe --typecheck not-equal.swift
  2:7: error: type 'E' does not conform to protocol 'Equatable'
  [1]
