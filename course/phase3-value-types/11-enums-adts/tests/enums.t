End-to-end: enums are tagged unions — compile with ./lab.exe and RUN, matching swiftc.
RED until SILGen's + IRGen's TODO(11) holes are filled.

A simple enum lowers to a one-field tagged union; equality compares the tag:

  $ cat > c.swift <<'EOF'
  > enum Color { case red, green, blue }
  > let c = Color.green
  > print(c == Color.green)
  > print(c == Color.red)
  > EOF
  $ ./lab.exe --emit-llvm c.swift | grep -c "%Color = type { i64 }"
  1
  $ ./lab.exe build c.swift -o c && ./c
  true
  false

A raw-value enum: `.rawValue` is the case's index (implicit raws start at 0):

  $ cat > d.swift <<'EOF'
  > enum Dir: Int { case north, south, east, west }
  > print(Dir.north.rawValue)
  > print(Dir.south.rawValue)
  > print(Dir.west.rawValue)
  > EOF
  $ ./lab.exe build d.swift -o d && ./d
  0
  1
  3

An associated-value enum sizes its payload to the widest case (tag + two i64 slots):

  $ cat > s.swift <<'EOF'
  > enum Shape {
  >   case circle(Int)
  >   case rect(Int, Int)
  >   case dot
  > }
  > let s = Shape.rect(3, 4)
  > EOF
  $ ./lab.exe --emit-llvm s.swift | grep -c "%Shape = type { i64, i64, i64 }"
  1
