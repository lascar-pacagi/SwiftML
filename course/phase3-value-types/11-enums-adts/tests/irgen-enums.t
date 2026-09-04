The irgen hole, TODO(11): the two enum instructions become LLVM aggregate operations — `enum`
an `insertvalue` chain (the tag at field 0, the payload after it), `enum_tag` an `extractvalue …
, 0`. It needs the silgen holes too, since it lowers what SILGen produced; from "runs" on, the
programs BUILD and RUN.

A payload-free enum is a one-field aggregate — the tag alone — and a case is one `insertvalue`:

  $ cat > color.swift <<'EOF'
  > enum Color { case red, green, blue }
  > let c = Color.green
  > EOF
  $ ./lab.exe --emit-llvm color.swift | grep -E '= type|insertvalue'
  %Color = type { i64 }
    %t1 = insertvalue %Color undef, i64 1, 0

An enum sizes its payload to the WIDEST case: `rect(Int, Int)` gives Shape two payload words,
and `circle(5)` leaves the second one undefined:

  $ cat > shape.swift <<'EOF'
  > enum Shape {
  >   case circle(Int)
  >   case rect(Int, Int)
  >   case dot
  > }
  > let s = Shape.circle(5)
  > EOF
  $ ./lab.exe --emit-llvm shape.swift | grep -E '= type|insertvalue'
  %Shape = type { i64, i64, i64 }
    %t1 = insertvalue %Shape undef, i64 0, 0
    %t2 = insertvalue %Shape %t1, i64 5, 1

A two-value payload fills both slots, in order, after the tag at 0:

  $ cat > rect.swift <<'EOF'
  > enum Shape {
  >   case circle(Int)
  >   case rect(Int, Int)
  > }
  > let s = Shape.rect(3, 4)
  > EOF
  $ ./lab.exe --emit-llvm rect.swift | grep insertvalue
    %t1 = insertvalue %Shape undef, i64 1, 0
    %t2 = insertvalue %Shape %t1, i64 3, 1
    %t3 = insertvalue %Shape %t2, i64 4, 2

`enum_tag` is `extractvalue … , 0`, and `Dir.south.rawValue` reads it straight out of the
freshly built value — no slot, no `load` in between:

  $ cat > tag.swift <<'EOF'
  > enum Dir: Int { case north, south }
  > print(Dir.south.rawValue)
  > EOF
  $ ./lab.exe --emit-llvm tag.swift | grep -E 'extractvalue|load'
    %t1 = extractvalue %Dir %t0, 0

Runs: `==` on a payload-free enum is a tag compare — `green == green` is true, `green == red`
is false:

  $ cat > eq.swift <<'EOF'
  > enum Color { case red, green, blue }
  > let c = Color.green
  > print(c == Color.green)
  > print(c == Color.red)
  > EOF
  $ ./lab.exe build eq.swift -o eq && ./eq
  true
  false

Runs: implicit raw values start at 0 and follow the declaration order — north 0, south 1,
west 3:

  $ cat > raw.swift <<'EOF'
  > enum Dir: Int { case north, south, east, west }
  > print(Dir.north.rawValue)
  > print(Dir.south.rawValue)
  > print(Dir.west.rawValue)
  > EOF
  $ ./lab.exe build raw.swift -o raw && ./raw
  0
  1
  3

Runs: `case a, b, c` on one line numbers left to right — a case list built in reverse would
still compile and still pass every shape test, and only the raw values would show it:

  $ cat > order.swift <<'EOF'
  > enum D: Int { case a, b, c, d }
  > print(D.a.rawValue)
  > print(D.d.rawValue)
  > EOF
  $ ./lab.exe build order.swift -o order && ./order
  0
  3

Runs: an enum lives in a `var`, is reassigned, and drives an `if` — the tag is all it takes:

  $ cat > flow.swift <<'EOF'
  > enum Light { case red, green }
  > var l = Light.red
  > var n = 0
  > while n < 3 {
  >   if l == Light.red { l = Light.green } else { l = Light.red }
  >   n = n + 1
  > }
  > print(l == Light.green)
  > EOF
  $ ./lab.exe build flow.swift -o flow && ./flow
  true

Runs: an enum goes into and out of a function BY VALUE, like a struct:

  $ cat > fn.swift <<'EOF'
  > enum Color { case red, green }
  > func flip(_ c: Color) -> Color {
  >   if c == Color.red { return Color.green }
  >   return Color.red
  > }
  > print(flip(Color.red) == Color.green)
  > print(flip(flip(Color.red)) == Color.red)
  > EOF
  $ ./lab.exe build fn.swift -o fn && ./fn
  true
  true

Runs: an associated-value enum can be BUILT and passed around here; taking it apart is
concept 12's `switch`, so all this program can observe is that it compiled and ran:

  $ cat > payload.swift <<'EOF'
  > enum Shape {
  >   case circle(Int)
  >   case rect(Int, Int)
  >   case dot
  > }
  > func area(_ s: Shape) -> Int { return 0 }
  > let a = Shape.circle(5)
  > let b = Shape.rect(3, 4)
  > print(area(a) + area(b))
  > EOF
  $ ./lab.exe build payload.swift -o payload && ./payload
  0
