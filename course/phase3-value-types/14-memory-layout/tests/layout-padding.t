The first hole, TODO(14a): the padding walk that gives a struct its SIZE and ALIGNMENT. Each
field starts at the next offset that satisfies its own alignment, the struct's alignment is the
widest of its fields', and the size is where the last field ends. `--emit-layout` runs the front
end and prints the layout of every scalar and every declared type, so it needs no lowering — but
it prints offsets too, so this file goes green together with `layout-offsets.t`; the alcotest
`layout-padding` group calls `Layout.struct_info` directly and is reachable on this hole alone.

The scalars are the base cases, and they are given: `Int` and `Double` are 8-byte, `Bool` is a
single byte whose alignment is 1. `--emit-layout` dumps every declared type after them, so a
one-field struct shows up too — and a struct of one `Int` is exactly an `Int`:

  $ cat > scalars.swift <<'EOF'
  > struct One {
  >   var x: Int
  > }
  > EOF
  $ ./lab.exe --emit-layout scalars.swift
  Int: size=8 stride=8 align=8
  Bool: size=1 stride=1 align=1
  Double: size=8 stride=8 align=8
  One: size=8 stride=8 align=8
    .x offset=0

Two `Int`s pack with no padding at all — 16 bytes, aligned 8:

  $ cat > p.swift <<'EOF'
  > struct P {
  >   var x: Int
  >   var y: Int
  > }
  > EOF
  $ ./lab.exe --emit-layout p.swift | grep '^P:'
  P: size=16 stride=16 align=8

FIELD ORDER CHANGES THE SIZE. `{Bool, Int}` pads the Bool out to 8 so the Int lands on its
alignment, and ends at 16. `{Int, Bool}` needs no padding — it ends at 9:

  $ cat > order.swift <<'EOF'
  > struct BoolFirst {
  >   var b: Bool
  >   var i: Int
  > }
  > struct IntFirst {
  >   var i: Int
  >   var b: Bool
  > }
  > EOF
  $ ./lab.exe --emit-layout order.swift | grep -E '^(BoolFirst|IntFirst):'
  BoolFirst: size=16 stride=16 align=8
  IntFirst: size=9 stride=16 align=8

SIZE is not STRIDE: `IntFirst` is 9 bytes of content, but the next element of an array of them
has to start on an 8-byte boundary, so the stride is 16. `size` is what you copy, `stride` is
how far apart they sit:

  $ ./lab.exe --emit-layout order.swift | grep '^IntFirst:'
  IntFirst: size=9 stride=16 align=8

Bools cost one byte each and align to 1, so three of them fit in three bytes:

  $ cat > flags.swift <<'EOF'
  > struct Flags {
  >   var a: Bool
  >   var b: Bool
  >   var c: Bool
  > }
  > EOF
  $ ./lab.exe --emit-layout flags.swift | grep '^Flags:'
  Flags: size=3 stride=3 align=1

A struct field carries its OWN alignment into the walk: `Outer` starts with a Bool, then pads to
8 for an `Inner` that is itself 8-aligned and 16 wide, so `Outer` is 24:

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
  $ ./lab.exe --emit-layout nest.swift | grep -E '^(Inner|Outer):'
  Inner: size=16 stride=16 align=8
  Outer: size=24 stride=24 align=8

The naive tagged union: an enum is a tag WORD plus payload words sized to the widest case, and
an `Int?` is `{ i64 tag, Int }` = 16. This is where we DIVERGE from swiftc, which packs the tag
into the payload's spare bits and gets 9 for `Int?` (§2) — which is why the oracle keeps to
structs of scalars:

  $ cat > tagged.swift <<'EOF'
  > enum Color { case red, green }
  > enum Shape {
  >   case circle(Int)
  >   case rect(Int, Int)
  > }
  > struct Maybe {
  >   var v: Int?
  > }
  > EOF
  $ ./lab.exe --emit-layout tagged.swift | grep -E '^(Color|Shape|Maybe):'
  Maybe: size=16 stride=16 align=8
  Color: size=8 stride=8 align=8
  Shape: size=24 stride=24 align=8
