The struct rules of sema — GIVEN code, so this file is green from the start; it is here so
the diagnostics the front end owes you are on record before you lower anything. `--typecheck`
stops after sema: exit 0 and silence is "accepted", exit 1 with `line:col: error: …` is not.

A well-formed struct program (declaration, memberwise init, reads, a field write) is accepted:

  $ cat > ok.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 1, y: 2)
  > p.x = p.y + 1
  > let q = p
  > print(q.x)
  > EOF
  $ ./lab.exe --typecheck ok.swift

`Point(1, 2)` is missing its labels: one `missing argument label` per positional argument:

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

`Point(z: 1, y: 2)` names a wrong label: `incorrect argument label in call (have 'z:', …)`:

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

`Point(x: 1)` has one argument for two fields: the initializer's arity is reported:

  $ cat > arity.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(x: 1)
  > EOF
  $ ./lab.exe --typecheck arity.swift
  5:9: error: 'Point' initializer expects 2 argument(s) but 1 given
  [1]

`Point(x: "s", y: 2)` checks each argument against its field's type:

  $ cat > argty.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(x: "s", y: 2)
  > EOF
  $ ./lab.exe --typecheck argty.swift
  5:18: error: cannot convert value of type 'String' to specified type 'Int'
  [1]

`p.z` on a Point is `value of type 'Point' has no member 'z'`; `n.x` on an Int likewise:

  $ cat > nomember.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(x: 1, y: 2)
  > print(p.z)
  > let n = 3
  > print(n.x)
  > EOF
  $ ./lab.exe --typecheck nomember.swift
  6:7: error: value of type 'Point' has no member 'z'
  8:7: error: value of type 'Int' has no member 'x'
  [1]

`p.x = 5` on a `let p` is rejected — the binding is immutable, so its fields are too:

  $ cat > letbind.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(x: 1, y: 2)
  > p.x = 5
  > EOF
  $ ./lab.exe --typecheck letbind.swift
  6:1: error: cannot assign to property: 'p' is a 'let' constant
  [1]

`s.x = 2` on a `let x` field is rejected even through a `var s` — the FIELD is immutable:

  $ cat > letfield.swift <<'EOF'
  > struct S {
  >   let x: Int
  >   var y: Int
  > }
  > var s = S(x: 1, y: 2)
  > s.y = 3
  > s.x = 2
  > EOF
  $ ./lab.exe --typecheck letfield.swift
  7:1: error: cannot assign to property: 'x' is a 'let' constant
  [1]

`p == q` on two Points is rejected: a struct is not Equatable until you say so (Exercise 3):

  $ cat > eq.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(x: 1, y: 2)
  > let q = p
  > print(p == q)
  > EOF
  $ ./lab.exe --typecheck eq.swift
  7:7: error: binary operator '==' cannot be applied to two 'Point' operands
  [1]

`print(p)` of a whole struct is refused up front (swiftc prints `Point(x: 1, y: 2)` — a
documented divergence, §2) instead of crashing IRGen:

  $ cat > printstruct.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(x: 1, y: 2)
  > print(p)
  > EOF
  $ ./lab.exe --typecheck printstruct.swift
  6:7: error: cannot print a value of type 'Point' (only Int, Double, Bool and String)
  [1]

A field of an undeclared type and a struct declared twice are both reported:

  $ cat > decl.swift <<'EOF'
  > struct A {
  >   var v: Nope
  > }
  > struct A {
  >   var w: Int
  > }
  > EOF
  $ ./lab.exe --typecheck decl.swift
  4:1: error: invalid redeclaration of 'A'
  1:1: error: cannot find type 'Nope' in scope
  [1]
