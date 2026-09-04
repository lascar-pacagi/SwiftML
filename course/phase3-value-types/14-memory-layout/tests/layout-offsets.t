The second hole, TODO(14b): the byte OFFSET of each stored property — the same padding walk as
`TODO(14a)`, remembering where each field starts instead of only where the last one ends. This
is what `MemoryLayout<T>.offset(of: \T.field)` reports, and `oracle.t` checks ours against it.
`--emit-layout` prints an indented `.field offset=N` line under each struct.

Two `Int`s start at 0 and 8 — the offsets are the running total when nothing needs padding:

  $ cat > p.swift <<'EOF'
  > struct P {
  >   var x: Int
  >   var y: Int
  > }
  > EOF
  $ ./lab.exe --emit-layout p.swift
  Int: size=8 stride=8 align=8
  Bool: size=1 stride=1 align=1
  Double: size=8 stride=8 align=8
  P: size=16 stride=16 align=8
    .x offset=0
    .y offset=8

The FIRST field is always at 0, whatever it is, and the padding shows up as a gap between two
offsets: `.b` at 0, then `.i` at 8, with bytes 1..7 unused:

  $ cat > pad.swift <<'EOF'
  > struct BoolFirst {
  >   var b: Bool
  >   var i: Int
  > }
  > EOF
  $ ./lab.exe --emit-layout pad.swift | grep -A2 '^BoolFirst:'
  BoolFirst: size=16 stride=16 align=8
    .b offset=0
    .i offset=8

Bools need no padding between them, so they are consecutive — and the `Int` after them still
jumps to 8:

  $ cat > three.swift <<'EOF'
  > struct Three {
  >   var a: Bool
  >   var b: Bool
  >   var c: Int
  > }
  > EOF
  $ ./lab.exe --emit-layout three.swift | grep -A3 '^Three:'
  Three: size=16 stride=16 align=8
    .a offset=0
    .b offset=1
    .c offset=8

A nested struct occupies ONE field slot at its own alignment: `.inner` starts at 8, not at 1:

  $ cat > nest.swift <<'EOF'
  > struct Inner {
  >   var a: Bool
  >   var b: Int
  > }
  > struct Outer {
  >   var flag: Bool
  >   var inner: Inner
  > }
  > EOF
  $ ./lab.exe --emit-layout nest.swift | grep -A2 '^Outer:'
  Outer: size=24 stride=24 align=8
    .flag offset=0
    .inner offset=8

Padding in the MIDDLE is what a mixed struct costs: `.i` 0, `.b` 8, `.j` 16, `.c` 24 — seven
wasted bytes after each Bool, and 32 bytes for 18 bytes of content:

  $ cat > wide.swift <<'EOF'
  > struct Wide {
  >   var i: Int
  >   var b: Bool
  >   var j: Int
  >   var c: Bool
  > }
  > EOF
  $ ./lab.exe --emit-layout wide.swift | grep -A4 '^Wide:'
  Wide: size=25 stride=32 align=8
    .i offset=0
    .b offset=8
    .j offset=16
    .c offset=24
