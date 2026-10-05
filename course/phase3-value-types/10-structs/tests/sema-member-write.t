TODO(10f) member assignment — Sema checks the base binding, the field, mutability at both
levels, and the assigned value's type.

A `var` property through a `var` struct binding accepts a value of the field type.

  $ cat > ok.swift <<'EOF'
  > struct Point {
  >   var x: Int
  > }
  > var p = Point(x: 1)
  > p.x = 5
  > EOF
  $ ./lab.exe --typecheck ok.swift

A `let` struct binding makes even its `var` properties immutable.

  $ cat > letbind.swift <<'EOF'
  > struct Point {
  >   var x: Int
  > }
  > let p = Point(x: 1)
  > p.x = 5
  > EOF
  $ ./lab.exe --typecheck letbind.swift
  5:1: error: cannot assign to property: 'p' is a 'let' constant
  p.x = 5
  ^
  [1]

A `let` property remains immutable through a `var` binding.

  $ cat > letfield.swift <<'EOF'
  > struct Pair {
  >   let first: Int
  >   var second: Int
  > }
  > var pair = Pair(first: 1, second: 2)
  > pair.second = 3
  > pair.first = 4
  > EOF
  $ ./lab.exe --typecheck letfield.swift
  7:1: error: cannot assign to property: 'first' is a 'let' constant
  pair.first = 4
  ^
  [1]

The assigned expression is checked against the property's declared type.

  $ cat > value.swift <<'EOF'
  > struct Point {
  >   var x: Int
  > }
  > var p = Point(x: 1)
  > p.x = "wrong"
  > EOF
  $ ./lab.exe --typecheck value.swift
  5:7: error: cannot convert value of type 'String' to specified type 'Int'
  p.x = "wrong"
        ^
  [1]

Writing a member of a variable that was never declared, `q.x = 1`, reports `q` itself, as
swiftc does.

  $ printf 'struct P {\n  var x: Int\n}\nq.x = 1\n' > undeclared.swift
  $ ./lab.exe --typecheck undeclared.swift
  4:1: error: cannot find 'q' in scope
  q.x = 1
  ^
  [1]

Writing a member of a value whose type is unknown reports nothing more: `var p: Nope` is the one
error, and `p.x = true` checks its right-hand side against that unknown type:

  $ cat > unknown-base.swift <<'EOF'
  > var p: Nope = 1
  > p.x = true
  > EOF
  $ ./lab.exe --typecheck unknown-base.swift
  1:1: error: cannot find type 'Nope' in scope
  var p: Nope = 1
  ^
  [1]

When both the binding and the field are `let`, the FIELD is named, as swiftc does: the
field is immutable whatever the binding.

  $ cat > let-let.swift <<'EOF'
  > struct S {
  >   let a: Int
  > }
  > let s = S(a: 1)
  > s.a = 2
  > EOF
  $ ./lab.exe --typecheck let-let.swift
  5:1: error: cannot assign to property: 'a' is a 'let' constant
  s.a = 2
  ^
  [1]

Writing a field the struct does not have names the struct's TYPE, `Point`, not the
variable `p`.

  $ cat > write-unknown-field.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 1, y: 2)
  > p.z = 1
  > EOF
  $ ./lab.exe --typecheck write-unknown-field.swift
  6:1: error: value of type 'Point' has no member 'z'
  p.z = 1
  ^
  [1]

An `Int` has no fields to write either.

  $ cat > write-int-member.swift <<'EOF'
  > var n = 3
  > n.x = 1
  > EOF
  $ ./lab.exe --typecheck write-int-member.swift
  2:1: error: value of type 'Int' has no member 'x'
  n.x = 1
  ^
  [1]

A struct-typed field takes a whole struct value, and nothing else.

  $ cat > write-struct-field.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > struct Line {
  >   var a: Point
  >   var b: Point
  > }
  > var l = Line(a: Point(x: 1, y: 2), b: Point(x: 3, y: 4))
  > l.a = Point(x: 9, y: 9)
  > l.b = 3
  > EOF
  $ ./lab.exe --typecheck write-struct-field.swift
  11:7: error: cannot convert value of type 'Int' to specified type 'Point'
  l.b = 3
        ^
  [1]

A parameter is a constant: writing one of its fields is refused, naming the parameter.

  $ cat > write-param.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > func f(_ p: Point) {
  >   p.x = 1
  > }
  > EOF
  $ ./lab.exe --typecheck write-param.swift
  6:3: error: cannot assign to property: 'p' is a 'let' constant
    p.x = 1
    ^
  [1]

Replacing a whole `let` struct is the variable rule of concept 05, not a property rule:
"cannot assign to value".

  $ cat > let-whole.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(x: 1, y: 2)
  > p = Point(x: 3, y: 4)
  > EOF
  $ ./lab.exe --typecheck let-whole.swift
  6:1: error: cannot assign to value: 'p' is a 'let' constant
  p = Point(x: 3, y: 4)
  ^
  [1]
