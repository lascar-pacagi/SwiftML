TODO(10e) struct expressions — a member read obtains its type from the registered layout. The
memberwise initializer's checks (one labeled value per field, in declaration order) are given
code, tested here because they need the registry and the member read.

A field read takes its type from the struct's layout: `pair.count` is an `Int`, `pair.ready` a
`Bool`, so both functions type-check. (The structs arrive as parameters, so no `Pair(…)` is built.)

  $ cat > member-types.swift <<'EOF'
  > struct Pair {
  >   var count: Int
  >   var ready: Bool
  > }
  > func count(_ pair: Pair) -> Int { return pair.count }
  > func ready(_ pair: Pair) -> Bool { return pair.ready }
  > EOF
  $ ./lab.exe --typecheck member-types.swift

Reading a field `Point` does not have, `point.z`, is an error, and it points at the field NAME
`z` (column 49), as swiftc does — not at `point` or at the `.`.

  $ cat > unknown-member.swift <<'EOF'
  > struct Point {
  >   var x: Int
  > }
  > func read(_ point: Point) -> Int { return point.z }
  > EOF
  $ ./lab.exe --typecheck unknown-member.swift > member.err 2>&1; rc=$?; cat member.err; echo "exit=$rc"
  4:49: error: value of type 'Point' has no member 'z'
  func read(_ point: Point) -> Int { return point.z }
                                                  ^
  exit=1

An `Int` has no fields, so `number.x` is the same error, again at the name `x` (column 49).

  $ printf 'func read(_ number: Int) -> Int { return number.x }\n' > scalar-member.swift
  $ ./lab.exe --typecheck scalar-member.swift > scalar.err 2>&1; rc=$?; cat scalar.err; echo "exit=$rc"
  1:49: error: value of type 'Int' has no member 'x'
  func read(_ number: Int) -> Int { return number.x }
                                                  ^
  exit=1

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
  let p = Point(1, 2)
                ^
  5:18: error: missing argument label 'y:' in call
  let p = Point(1, 2)
                   ^
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
  let p = Point(z: 1, y: 2)
                   ^
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
  let short = Point(x: 1)
              ^
  6:25: error: cannot convert value of type 'String' to specified type 'Int'
  let mistyped = Point(x: "s", y: 2)
                          ^
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
  5:9: error: value of type 'Point' has no member 'z'
  print(p.z)
          ^
  7:9: error: value of type 'Int' has no member 'x'
  print(n.x)
          ^
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
  print(p == q)
        ^
  7:7: error: cannot print a value of type 'Point' (only Int, Double, Bool and String)
  print(p)
        ^
  [1]

A member of a value whose type is unknown is itself unknown: `let p: Nope = …` is reported once,
and `p.y` — which no struct declares — read as a Bool adds nothing:

  $ cat > unknown-base.swift <<'EOF'
  > struct Point {
  >   var x: Int
  > }
  > let p: Nope = Point(x: 1)
  > let q: Bool = p.y
  > EOF
  $ ./lab.exe --typecheck unknown-base.swift
  4:1: error: cannot find type 'Nope' in scope
  let p: Nope = Point(x: 1)
  ^
  [1]
