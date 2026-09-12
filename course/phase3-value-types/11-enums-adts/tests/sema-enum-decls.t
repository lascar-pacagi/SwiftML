TODO(11d) enum registry — Sema first records every enum name, then resolves its ordered
case layouts. This permits forward references from function signatures.

An enum type may appear in a function signature before its declaration.

  $ cat > forward.swift <<'EOF'
  > func identity(_ command: Command) -> Command {
  >   return command
  > }
  > enum Command {
  >   case stop
  >   case move(Int, Int)
  > }
  > EOF
  $ ./lab.exe --typecheck forward.swift

This concept's runtime layout has Int payload slots, so another associated-value type is
rejected before it reaches IRGen.

  $ printf 'enum Flag { case value(Bool) }\n' > payload-type.swift
  $ ./lab.exe --typecheck payload-type.swift
  1:1: error: associated value type 'Bool' is not supported (only Int)
  [1]

Only `Int` is implemented as a raw type in this concept.

  $ printf 'enum Flag: Bool { case off, on }\n' > raw-type.swift
  $ ./lab.exe --typecheck raw-type.swift
  1:1: error: raw type 'Bool' is not supported (only Int)
  [1]

An unknown associated-value type and a type-name redeclaration are both reported.

  $ cat > invalid.swift <<'EOF'
  > enum A { case value(Missing) }
  > struct A { var x: Int }
  > EOF
  $ ./lab.exe --typecheck invalid.swift
  2:1: error: invalid redeclaration of 'A'
  1:1: error: cannot find type 'Missing' in scope
  [1]
