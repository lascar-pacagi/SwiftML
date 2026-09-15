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
  $ python3 timeout.py 2 ./lab.exe --typecheck forward.swift

A struct field may be typed by an enum declared LATER in the file. The first walk registers
every name before any layout is read, so a declaration written above an enum can still name it.

  $ cat > later.swift <<'EOF'
  > struct Task {
  >   var level: Level
  > }
  > enum Level {
  >   case low
  >   case high
  > }
  > let t = Task(level: Level.high)
  > EOF
  $ python3 timeout.py 2 ./lab.exe --typecheck later.swift

A case the enum does not declare is reported against it, not accepted by the empty placeholder.
Registering the name is only half of PASS 0; the case list arrives in the second walk.

  $ cat > unknown-later.swift <<'EOF'
  > struct Task {
  >   var level: Level
  > }
  > enum Level {
  >   case low
  > }
  > let t = Task(level: Level.high)
  > EOF
  $ python3 timeout.py 2 ./lab.exe --typecheck unknown-later.swift
  7:21: error: type 'Level' has no member 'high'
  let t = Task(level: Level.high)
                      ^
  [1]

This concept's runtime layout has Int payload slots, so another associated-value type is
rejected before it reaches IRGen.

  $ printf 'enum Flag { case value(Bool) }\n' > payload-type.swift
  $ python3 timeout.py 2 ./lab.exe --typecheck payload-type.swift
  1:1: error: associated value type 'Bool' is not supported (only Int)
  enum Flag { case value(Bool) }
  ^
  [1]

Only `Int` is implemented as a raw type in this concept.

  $ printf 'enum Flag: Bool { case off, on }\n' > raw-type.swift
  $ python3 timeout.py 2 ./lab.exe --typecheck raw-type.swift
  1:1: error: raw type 'Bool' is not supported (only Int)
  enum Flag: Bool { case off, on }
  ^
  [1]

An unknown associated-value type and a type-name redeclaration are both reported.

  $ cat > invalid.swift <<'EOF'
  > enum A { case value(Missing) }
  > struct A { var x: Int }
  > EOF
  $ python3 timeout.py 2 ./lab.exe --typecheck invalid.swift
  2:1: error: invalid redeclaration of 'A'
  struct A { var x: Int }
  ^
  1:1: error: cannot find type 'Missing' in scope
  enum A { case value(Missing) }
  ^
  [1]
