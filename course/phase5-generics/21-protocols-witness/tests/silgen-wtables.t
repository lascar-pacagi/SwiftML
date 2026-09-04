The witness tables, through `--emit-sil`. Needs `TODO(21c)`, the `wtables` of `lower`: one
`sil_witness_table S: P` per conformance clause, listing the implementing function of each
requirement IN REQUIREMENT ORDER — that order is the slot numbering dispatch indexes into.
Every SIL module lowers through this hole, so it is the one to fill first; these programs
never wrap a value or call a method, so they need nothing else.

One conformer, one requirement: one table with one slot:

  $ cat > one.swift <<'EOF'
  > protocol Shape { func area() -> Int }
  > struct Circle: Shape {
  >   var r: Int
  >   func area() -> Int { return 3 * r * r }
  > }
  > print(1)
  > EOF
  $ ./lab.exe --emit-sil one.swift | grep -A2 'sil_witness_table'
  sil_witness_table Circle: Shape {
    #0: @Circle.area
  }

Slots follow the REQUIREMENT order, not the order the methods were written in:

  $ cat > order.swift <<'EOF'
  > protocol Shape {
  >   func area() -> Int
  >   func perimeter() -> Int
  >   func name() -> Int
  > }
  > struct Square: Shape {
  >   var s: Int
  >   func name() -> Int { return 4 }
  >   func perimeter() -> Int { return 4 * s }
  >   func extra() -> Int { return 0 }
  >   func area() -> Int { return s * s }
  > }
  > print(1)
  > EOF
  $ ./lab.exe --emit-sil order.swift | grep -A4 'sil_witness_table'
  sil_witness_table Square: Shape {
    #0: @Square.area
    #1: @Square.perimeter
    #2: @Square.name
  }

Two conformers of one protocol: two tables, each naming its own methods:

  $ cat > two.swift <<'EOF'
  > protocol Shape { func area() -> Int }
  > struct Circle: Shape {
  >   var r: Int
  >   func area() -> Int { return 3 * r * r }
  > }
  > struct Square: Shape {
  >   var s: Int
  >   func area() -> Int { return s * s }
  > }
  > print(1)
  > EOF
  $ ./lab.exe --emit-sil two.swift | grep -A2 'sil_witness_table'
  sil_witness_table Circle: Shape {
    #0: @Circle.area
  }
  --
  sil_witness_table Square: Shape {
    #0: @Square.area
  }

One struct conforming to two protocols: one table PER CONFORMANCE, in clause order:

  $ cat > pq.swift <<'EOF'
  > protocol P { func p() -> Int }
  > protocol Q { func q() -> Int }
  > struct Both: P, Q {
  >   func q() -> Int { return 2 }
  >   func p() -> Int { return 1 }
  > }
  > print(1)
  > EOF
  $ ./lab.exe --emit-sil pq.swift | grep -A2 'sil_witness_table'
  sil_witness_table Both: P {
    #0: @Both.p
  }
  --
  sil_witness_table Both: Q {
    #0: @Both.q
  }

A struct with methods but no conformance clause gets no table (the protocol alone is not a
conformance), and a protocol-free program prints no table at all:

  $ cat > none.swift <<'EOF'
  > protocol Shape { func area() -> Int }
  > struct Loner {
  >   var r: Int
  >   func area() -> Int { return r }
  > }
  > print(Loner(r: 1).r)
  > EOF
  $ ./lab.exe --emit-sil none.swift | grep -c 'sil_witness_table' || true
  0
  $ printf 'let x = 2\nprint(x * 21)\n' > plain.swift
  $ ./lab.exe --emit-sil plain.swift | grep -c 'sil_witness_table' || true
  0

The method bodies the tables point at are ordinary SIL functions named `S.m`, self first:

  $ ./lab.exe --emit-sil two.swift | grep '^sil @'
  sil @Circle.area(%0 : $Circle) -> $Int {
  sil @Square.area(%0 : $Square) -> $Int {
  sil @main() -> $() {
