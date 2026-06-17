Protocols, conformances, witness tables, dynamic dispatch — end-to-end vs swiftc. RED until
the TODO(21) holes are filled (sema: the conformance check; silgen: wrap/dispatch/tables).

The SIL shows the witness tables and both dispatch forms:

  $ cat > s.swift <<'EOF'
  > protocol Shape { func area() -> Int }
  > struct Circle: Shape {
  >   var r: Int
  >   func area() -> Int { return 3 * r * r }
  > }
  > let c = Circle(r: 2)
  > print(c.area())
  > let s: Shape = c
  > print(s.area())
  > EOF
  $ ./lab.exe --emit-sil s.swift | grep -A2 'sil_witness_table'
  sil_witness_table Circle: Shape {
    #0: @Circle.area
  }
  $ ./lab.exe --emit-sil s.swift | grep -c 'init_existential'
  1
  $ ./lab.exe --emit-sil s.swift | grep -c 'witness_method'
  1

Static dispatch on the concrete value, dynamic through the table — same answers as swiftc:

  $ ./lab.exe build s.swift -o s && ./s
  12
  12

Heterogeneous dispatch — one call site, two concrete types (this is the point of the table):

  $ cat > h.swift <<'EOF'
  > protocol Shape { func area() -> Int }
  > struct Circle: Shape {
  >   var r: Int
  >   func area() -> Int { return 3 * r * r }
  > }
  > struct Square: Shape {
  >   var s: Int
  >   func area() -> Int { return s * s }
  > }
  > func total(_ a: Shape, _ b: Shape) -> Int { return a.area() + b.area() }
  > print(total(Circle(r: 1), Square(s: 4)))
  > var z: Shape = Circle(r: 3)
  > print(z.area())
  > z = Square(s: 2)
  > print(z.area())
  > EOF
  $ ./lab.exe build h.swift -o h && ./h
  19
  27
  4
  $ ./lab.exe build h.swift -O -o hO && ./hO
  19
  27
  4

Conformance failures are rejected with swiftc's words:

  $ printf 'protocol S { func area() -> Int }\nstruct C: S { var r: Int }\n' > c1.swift
  $ ./lab.exe --typecheck c1.swift 2>&1 | head -1
  2:1: error: type 'C' does not conform to protocol 'S'

  $ cat > c2.swift <<'EOF'
  > protocol S { func area() -> Int }
  > struct C: S {
  >   var r: Int
  >   func area() -> Bool { return true }
  > }
  > EOF
  $ ./lab.exe --typecheck c2.swift 2>&1 | head -1
  2:1: error: type 'C' does not conform to protocol 'S'

An existential only exposes its protocol's requirements:

  $ cat > c3.swift <<'EOF'
  > protocol S { func area() -> Int }
  > struct C: S {
  >   var r: Int
  >   func area() -> Int { return r }
  >   func extra() -> Int { return 1 }
  > }
  > let s: S = C(r: 1)
  > print(s.extra())
  > EOF
  $ ./lab.exe --typecheck c3.swift 2>&1 | head -1
  8:7: error: value of type 'any S' has no member 'extra'

A non-mutating method cannot write a stored property:

  $ printf 'struct C { var x: Int\n  func bump() { x = x + 1 } }\n' > c4.swift
  $ ./lab.exe --typecheck c4.swift 2>&1 | head -1
  2:17: error: cannot assign to property: 'self' is immutable
