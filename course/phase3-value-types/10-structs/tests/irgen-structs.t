The irgen hole, TODO(10): the three struct instructions become LLVM aggregate operations —
`struct` an `insertvalue` chain from `undef`, `struct_extract` an `extractvalue`,
`struct_element_addr` a `getelementptr`. The first case needs only construction (given in
SILGen); the rest need both silgen holes too, and from "runs" on they BUILD and RUN.

A struct is a named LLVM type, and `Point(x: 3, y: 4)` is built by inserting each field into
`undef` in order — one `insertvalue` per field, the last one stored into the slot:

  $ cat > build.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(x: 3, y: 4)
  > EOF
  $ ./lab.exe --emit-llvm build.swift | grep -E '%Point = type|insertvalue|store %Point'
  %Point = type { i64, i64 }
    %t1 = insertvalue %Point undef, i64 3, 0
    %t2 = insertvalue %Point %t1, i64 4, 1
    store %Point %t2, ptr %t0

A nested struct is an aggregate OF aggregates: `%Line = type { %Point, %Point }`:

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
  > EOF
  $ ./lab.exe --emit-llvm nested.swift | grep -E '= type'
  %Point = type { i64, i64 }
  %Line = type { %Point, %Point }

Fields keep their own LLVM types: `{ double, i1 }` for a Double and a Bool:

  $ cat > mixed.swift <<'EOF'
  > struct M {
  >   var d: Double
  >   var ok: Bool
  > }
  > let m = M(d: 1.5, ok: true)
  > EOF
  $ ./lab.exe --emit-llvm mixed.swift | grep -E '= type|insertvalue'
  %M = type { double, i1 }
    %t1 = insertvalue %M undef, double 0x3FF8000000000000, 0
    %t2 = insertvalue %M %t1, i1 1, 1

A read `p.y` is `extractvalue %Point %v, 1` on the loaded aggregate:

  $ cat > read.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(x: 3, y: 4)
  > print(p.y)
  > EOF
  $ ./lab.exe --emit-llvm read.swift | grep -E 'load %Point|extractvalue'
    %t3 = load %Point, ptr %t0
    %t4 = extractvalue %Point %t3, 1

A write `p.x = 9` is `getelementptr %Point, ptr %slot, i32 0, i32 0` then a `store i64`:

  $ cat > write.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 1, y: 2)
  > p.x = 9
  > EOF
  $ ./lab.exe --emit-llvm write.swift | grep -E 'getelementptr|store i64 9'
    %t3 = getelementptr %Point, ptr %t0, i32 0, i32 0
    store i64 9, ptr %t3

Runs: `read.swift` above prints 4, and a program reading both fields prints 3 then 4:

  $ ./lab.exe build read.swift -o read && ./read
  4
  $ cat > both.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(x: 3, y: 4)
  > print(p.x)
  > print(p.y)
  > EOF
  $ ./lab.exe build both.swift -o both && ./both
  3
  4

Runs, value semantics: `var q = p; q.x = 99` leaves `p.x` at 1 — the copy is independent:

  $ cat > copy.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 1, y: 2)
  > var q = p
  > q.x = 99
  > print(p.x)
  > print(q.x)
  > EOF
  $ ./lab.exe build copy.swift -o copy && ./copy
  1
  99

Runs: a struct goes to a function BY VALUE, and a nested read `l.b.x` finds 7:

  $ cat > byval.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > struct Line {
  >   var a: Point
  >   var b: Point
  > }
  > func mx(_ l: Line) -> Int { return l.b.x }
  > print(mx(Line(a: Point(x: 0, y: 0), b: Point(x: 7, y: 9))))
  > EOF
  $ ./lab.exe build byval.swift -o byval && ./byval
  7

Runs: a function returning a struct, whose result is read and stored — `a` keeps 1, `b` is 2:

  $ cat > ret.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > func bump(_ p: Point) -> Point { return Point(x: p.x + 1, y: p.y + 1) }
  > let a = Point(x: 1, y: 1)
  > let b = bump(a)
  > print(a.x)
  > print(b.x)
  > EOF
  $ ./lab.exe build ret.swift -o ret && ./ret
  1
  2

Runs: field writes in a loop accumulate in the SAME slot — 0+1+2+3+4 = 10, 5 × 2 = 10:

  $ cat > loop.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 0, y: 0)
  > var i = 0
  > while i < 5 {
  >   p.x = p.x + i
  >   p.y = p.y + 2
  >   i = i + 1
  > }
  > print(p.x)
  > print(p.y)
  > EOF
  $ ./lab.exe build loop.swift -o loop && ./loop
  10
  10

Runs: `m.d * 2` with a Double field — the literal is generated AT Double, or clang rejects
`fmul double %d, 2` (a miscompile this test pins; Double prints via `%g`, so 3 not 3.0):

  $ cat > dbl.swift <<'EOF'
  > struct M {
  >   var d: Double
  >   var ok: Bool
  > }
  > let m = M(d: 1.5, ok: true)
  > print(m.d * 2)
  > print(m.ok)
  > EOF
  $ ./lab.exe build dbl.swift -o dbl && ./dbl
  3
  true
