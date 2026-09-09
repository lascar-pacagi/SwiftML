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
  [1]
