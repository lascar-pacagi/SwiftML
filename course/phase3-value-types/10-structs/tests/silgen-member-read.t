TODO(10g): a member READ `p.x` lowers to `struct_extract` on a struct
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
  $ ./lab.exe --emit-sil read.swift | sed -E 's/%[0-9]+/%v/g'
  struct Point { x: Int; y: Int }
  
  sil @main() -> $() {
  bb0:
    %v = integer_literal $Int, 3
    %v = integer_literal $Int, 4
    %v = struct (%v, %v) $Point
    %v = alloc_stack $Point  // p
    store %v to %v
    %v = load %v $Point
    %v = struct_extract %v, #0 $Int
    %v = apply @print(%v)
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
  $ ./lab.exe --emit-sil y.swift | grep struct_extract | sed -E 's/%[0-9]+/%v/g'
    %v = struct_extract %v, #1 $Int

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
  $ ./lab.exe --emit-sil mixed.swift | grep struct_extract | sed -E 's/%[0-9]+/%v/g'
    %v = struct_extract %v, #1 $Bool
    %v = struct_extract %v, #0 $Double

`Point(x: 1, y: 2).x` reads straight out of the built value — no slot, no load in between:

  $ cat > fresh.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > print(Point(x: 1, y: 2).x)
  > EOF
  $ ./lab.exe --emit-sil fresh.swift | grep -E 'struct|load' | sed -E 's/%[0-9]+/%v/g'
  struct Point { x: Int; y: Int }
    %v = struct (%v, %v) $Point
    %v = struct_extract %v, #0 $Int

`mk().y` extracts from a function's result the same way — any struct VALUE will do:

  $ cat > call.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > func mk() -> Point { return Point(x: 5, y: 6) }
  > print(mk().y)
  > EOF
  $ ./lab.exe --emit-sil call.swift | grep -E 'apply|struct_extract' | sed -E 's/%[0-9]+/%v/g'
    %v = apply %v()
    %v = struct_extract %v, #1 $Int
    %v = apply @print(%v)

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
  $ ./lab.exe --emit-sil nested.swift | grep struct_extract | sed -E 's/%[0-9]+/%v/g'
    %v = struct_extract %v, #1 $Point
    %v = struct_extract %v, #0 $Int

A read in a function body sees the PARAMETER's slot: `p.x + p.y` is two loads, two extracts:

  $ cat > fn.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > func sum(_ p: Point) -> Int { return p.x + p.y }
  > print(sum(Point(x: 1, y: 2)))
  > EOF
  $ ./lab.exe --emit-sil fn.swift | sed -n '/sil @sum/,/^}/p' | sed -E 's/%[0-9]+/%v/g'
  sil @sum(%v : $Point) -> $Int {
  bb0:
    %v = alloc_stack $Point  // p
    store %v to %v
    %v = load %v $Point
    %v = struct_extract %v, #0 $Int
    %v = load %v $Point
    %v = struct_extract %v, #1 $Int
    %v = binop "+" %v, %v $Int
    return %v
  }
