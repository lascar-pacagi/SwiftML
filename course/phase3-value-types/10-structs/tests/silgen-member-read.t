The first silgen hole, TODO(10): a member READ `p.x` lowers to `struct_extract` on a struct
VALUE. `--emit-sil` stops after SILGen, so this file needs no IRGen; it uses no field writes
(the second hole). Construction (`struct (…)`) and the load of a variable are given.

`print(p.x)` on `let p = Point(x: 3, y: 4)` loads p's slot, then `struct_extract %v, #0 $Int`:

  $ cat > read.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(x: 3, y: 4)
  > print(p.x)
  > EOF
  $ ./lab.exe --emit-sil read.swift
  struct Point { x: Int; y: Int }
  
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 3
    %1 = integer_literal $Int, 4
    %2 = struct (%0, %1) $Point
    %3 = alloc_stack $Point  // p
    store %2 to %3
    %5 = load %3 $Point
    %6 = struct_extract %5, #0 $Int
    %7 = apply @print(%6)
    return
  }

`p.y` is field #1 — the layout turns the NAME into the index, and the type comes with it:

  $ cat > y.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(x: 3, y: 4)
  > print(p.y)
  > EOF
  $ ./lab.exe --emit-sil y.swift | grep struct_extract
    %6 = struct_extract %5, #1 $Int

A field of a Bool and of a Double get their own types — `#1 $Bool`, `#0 $Double`:

  $ cat > mixed.swift <<'EOF'
  > struct M {
  >   var d: Double
  >   var ok: Bool
  > }
  > let m = M(d: 1.5, ok: true)
  > print(m.ok)
  > print(m.d)
  > EOF
  $ ./lab.exe --emit-sil mixed.swift | grep struct_extract
    %6 = struct_extract %5, #1 $Bool
    %9 = struct_extract %8, #0 $Double

`Point(x: 1, y: 2).x` reads straight out of the built value — no slot, no load in between:

  $ cat > fresh.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > print(Point(x: 1, y: 2).x)
  > EOF
  $ ./lab.exe --emit-sil fresh.swift | grep -E 'struct|load'
  struct Point { x: Int; y: Int }
    %2 = struct (%0, %1) $Point
    %3 = struct_extract %2, #0 $Int

`mk().y` extracts from a function's result the same way — any struct VALUE will do:

  $ cat > call.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > func mk() -> Point { return Point(x: 5, y: 6) }
  > print(mk().y)
  > EOF
  $ ./lab.exe --emit-sil call.swift | grep -E 'apply|struct_extract'
    %1 = apply %0()
    %2 = struct_extract %1, #1 $Int
    %3 = apply @print(%2)

`l.b.x` on a nested struct is two extracts: `#1` (the inner Point) then `#0` (its x):

  $ cat > nested.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > struct Line {
  >   var a: Point
  >   var b: Point
  > }
  > let l = Line(a: Point(x: 0, y: 0), b: Point(x: 7, y: 9))
  > print(l.b.x)
  > EOF
  $ ./lab.exe --emit-sil nested.swift | grep struct_extract
    %10 = struct_extract %9, #1 $Point
    %11 = struct_extract %10, #0 $Int

A read in a function body sees the PARAMETER's slot: `p.x + p.y` is two loads, two extracts:

  $ cat > fn.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > func sum(_ p: Point) -> Int { return p.x + p.y }
  > print(sum(Point(x: 1, y: 2)))
  > EOF
  $ ./lab.exe --emit-sil fn.swift | sed -n '/sil @sum/,/^}/p'
  sil @sum(%0 : $Point) -> $Int {
  bb0:
    %1 = alloc_stack $Point  // p
    store %0 to %1
    %3 = load %1 $Point
    %4 = struct_extract %3, #0 $Int
    %5 = load %1 $Point
    %6 = struct_extract %5, #1 $Int
    %7 = binop "+" %4, %6 $Int
    return %7
  }
