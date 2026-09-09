TODO(10e) struct expressions — a memberwise initializer checks one labeled value per field,
in declaration order, and a member read obtains its type from the registered layout.

A well-typed initializer and member read are accepted, including a nested read.

  $ cat > ok.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var visible: Bool
  > }
  > struct Box {
  >   var value: Point
  > }
  > let box = Box(value: Point(x: 3, visible: true))
  > print(box.value.x)
  > EOF
  $ ./lab.exe --typecheck ok.swift

Positional initializer arguments are each missing their stored property's label.

  $ cat > nolabel.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(1, 2)
  > EOF
  $ ./lab.exe --typecheck nolabel.swift
  5:15: error: missing argument label 'x:' in call
  5:18: error: missing argument label 'y:' in call
  [1]

A wrong label is compared with the corresponding field name.

  $ cat > badlabel.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(z: 1, y: 2)
  > EOF
  $ ./lab.exe --typecheck badlabel.swift
  5:18: error: incorrect argument label in call (have 'z:', expected 'x:')
  [1]

Initializer arity and argument types are checked before lowering.

  $ cat > badinit.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let short = Point(x: 1)
  > let mistyped = Point(x: "s", y: 2)
  > EOF
  $ ./lab.exe --typecheck badinit.swift
  5:13: error: 'Point' initializer expects 2 argument(s) but 1 given
  6:25: error: cannot convert value of type 'String' to specified type 'Int'
  [1]

An unknown field is diagnosed on a struct, and a scalar has no fields at all.

  $ cat > nomember.swift <<'EOF'
  > struct Point {
  >   var x: Int
  > }
  > let p = Point(x: 1)
  > print(p.z)
  > let n = 3
  > print(n.x)
  > EOF
  $ ./lab.exe --typecheck nomember.swift
  5:7: error: value of type 'Point' has no member 'z'
  7:7: error: value of type 'Int' has no member 'x'
  [1]

Whole-struct equality and printing are rejected because this backend cannot lower them yet.

  $ cat > guards.swift <<'EOF'
  > struct Point {
  >   var x: Int
  > }
  > let p = Point(x: 1)
  > let q = p
  > print(p == q)
  > print(p)
  > EOF
  $ ./lab.exe --typecheck guards.swift
  6:7: error: binary operator '==' cannot be applied to two 'Point' operands
  7:7: error: cannot print a value of type 'Point' (only Int, Double, Bool and String)
  [1]
