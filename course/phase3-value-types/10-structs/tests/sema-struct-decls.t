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

A field declared twice in one struct is a redeclaration, as any other name is. (It is
reported at the struct: a field carries no position of its own.)

  $ cat > dup-field.swift <<'EOF'
  > struct P {
  >   var x: Int
  >   var x: Int
  > }
  > EOF
  $ ./lab.exe --typecheck dup-field.swift
  1:1: error: invalid redeclaration of 'x'
  struct P {
  ^
  [1]

A struct may not contain itself: its size would be infinite. `N` holds an `N`.

  $ cat > self.swift <<'EOF'
  > struct N {
  >   var n: N
  > }
  > EOF
  $ ./lab.exe --typecheck self.swift
  1:1: error: value type 'N' cannot have a stored property that recursively contains it
  struct N {
  ^
  [1]

Containing itself THROUGH another struct is the same error, and each struct on the cycle
is reported once: `A` holds a `B`, which holds an `A`.

  $ cat > cycle.swift <<'EOF'
  > struct A {
  >   var b: B
  > }
  > struct B {
  >   var a: A
  > }
  > EOF
  $ ./lab.exe --typecheck cycle.swift
  1:1: error: value type 'A' cannot have a stored property that recursively contains it
  struct A {
  ^
  4:1: error: value type 'B' cannot have a stored property that recursively contains it
  struct B {
  ^
  [1]

One struct holding another, with no way back, is fine: `A` holds a `B`, and `B` holds an
`Int`.

  $ cat > no-cycle.swift <<'EOF'
  > struct A {
  >   var b: B
  > }
  > struct B {
  >   var x: Int
  > }
  > EOF
  $ ./lab.exe --typecheck no-cycle.swift

A struct that is not on a cycle but HOLDS one is infinite too: `A` holds a `B`, and `B` and `C`
hold each other. The check must keep track of the structs it has visited, or it never ends on
the `B`–`C` cycle while checking `A` (the 2-second limit turns that into a failure).

  $ cat > reaches-cycle.swift <<'EOF'
  > struct A {
  >   var b: B
  > }
  > struct B {
  >   var c: C
  > }
  > struct C {
  >   var b: B
  > }
  > EOF
  $ python3 timeout.py 2 ./lab.exe --typecheck reaches-cycle.swift
  1:1: error: value type 'A' has infinite size
  struct A {
  ^
  4:1: error: value type 'B' cannot have a stored property that recursively contains it
  struct B {
  ^
  7:1: error: value type 'C' cannot have a stored property that recursively contains it
  struct C {
  ^
  [1]
