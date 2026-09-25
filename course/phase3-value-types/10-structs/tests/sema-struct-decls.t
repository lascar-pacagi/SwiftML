TODO(10d) struct registry — Sema first records every struct name, then resolves the ordered
field layouts. This lets fields and function signatures refer to structs declared later.
`--typecheck` stops before SILGen.

Forward references between struct layouts and function signatures are accepted.

  $ cat > forward.swift <<'EOF'
  > func identity(_ box: Box) -> Box {
  >   return box
  > }
  > struct Box {
  >   var value: Point
  > }
  > struct Point {
  >   var x: Int
  > }
  > EOF
  $ ./lab.exe --typecheck forward.swift

A field of an undeclared type and a struct declared twice are both reported.

  $ cat > invalid.swift <<'EOF'
  > struct A {
  >   var value: Missing
  > }
  > struct A {
  >   var other: Int
  > }
  > EOF
  $ ./lab.exe --typecheck invalid.swift
  4:1: error: invalid redeclaration of 'A'
  struct A {
  ^
  1:1: error: cannot find type 'Missing' in scope
  struct A {
  ^
  [1]

A field of unknown type is reported once, on the declaration: initialising it with a Bool and
reading it back as a Bool add nothing, because the field's type is TError rather than a guess:

  $ cat > unknown-field.swift <<'EOF'
  > struct Point {
  >   var x: Nope
  > }
  > let p = Point(x: true)
  > let b: Bool = p.x
  > EOF
  $ ./lab.exe --typecheck unknown-field.swift
  1:1: error: cannot find type 'Nope' in scope
  struct Point {
  ^
  [1]
