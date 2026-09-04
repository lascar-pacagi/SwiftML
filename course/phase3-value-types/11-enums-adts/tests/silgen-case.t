The first silgen hole, TODO(11): a case with no associated values, `Color.red`, lowers to one
`enum #tag ()` instruction — the tag IS the case's index in the declaration. `--emit-sil` stops
after SILGen, so this file needs no IRGen; no program here carries a payload (that is the second
hole), so it can go green on its own.

`let c = Color.green` builds case #1 and stores it — `enum #1 () $Color`, then the usual slot:

  $ cat > green.swift <<'EOF'
  > enum Color { case red, green, blue }
  > let c = Color.green
  > EOF
  $ ./lab.exe --emit-sil green.swift
  enum Color { red; green; blue }
  
  sil @main() -> $() {
  bb0:
    %0 = enum #1 () $Color
    %1 = alloc_stack $Color  // c
    store %0 to %1
    return
  }

The tag is the DECLARATION order, and `case red, green, blue` on one line reads left to right —
red is #0, blue is #2:

  $ cat > order.swift <<'EOF'
  > enum Color { case red, green, blue }
  > let a = Color.red
  > let b = Color.blue
  > EOF
  $ ./lab.exe --emit-sil order.swift | grep enum
  enum Color { red; green; blue }
    %0 = enum #0 () $Color
    %3 = enum #2 () $Color

One case per line gives the same numbering — the line breaks are not what the tag counts:

  $ cat > lines.swift <<'EOF'
  > enum Color {
  >   case red
  >   case green
  >   case blue
  > }
  > let b = Color.blue
  > EOF
  $ ./lab.exe --emit-sil lines.swift | grep enum
  enum Color { red; green; blue }
    %0 = enum #2 () $Color

`c == Color.red` compares TAGS: an `enum_tag` of each side, then the integer `binop "=="`:

  $ cat > eq.swift <<'EOF'
  > enum Color { case red, green }
  > let c = Color.green
  > print(c == Color.red)
  > EOF
  $ ./lab.exe --emit-sil eq.swift
  enum Color { red; green }
  
  sil @main() -> $() {
  bb0:
    %0 = enum #1 () $Color
    %1 = alloc_stack $Color  // c
    store %0 to %1
    %3 = load %1 $Color
    %4 = enum #0 () $Color
    %5 = enum_tag %3
    %6 = enum_tag %4
    %7 = binop "==" %5, %6 $Bool
    %8 = apply @print(%7)
    return
  }

`.rawValue` on a `: Int` enum is the same `enum_tag` — with implicit raws the raw IS the tag:

  $ cat > raw.swift <<'EOF'
  > enum Dir: Int { case north, south, east, west }
  > print(Dir.west.rawValue)
  > EOF
  $ ./lab.exe --emit-sil raw.swift
  enum Dir { north; south; east; west }
  
  sil @main() -> $() {
  bb0:
    %0 = enum #3 () $Dir
    %1 = enum_tag %0
    %2 = apply @print(%1)
    return
  }

An enum in a `var` is a slot like any other value: the reassignment stores a new tag into it:

  $ cat > reassign.swift <<'EOF'
  > enum Color { case red, green }
  > var c = Color.red
  > c = Color.green
  > print(c == Color.green)
  > EOF
  $ ./lab.exe --emit-sil reassign.swift | grep -E 'enum|store'
  enum Color { red; green }
    %0 = enum #0 () $Color
    store %0 to %1
    %3 = enum #1 () $Color
    store %3 to %1
    %6 = enum #1 () $Color
    %7 = enum_tag %5
    %8 = enum_tag %6

An enum crosses a function boundary by value — a parameter slot in, a tag out:

  $ cat > fn.swift <<'EOF'
  > enum Color { case red, green }
  > func isRed(_ c: Color) -> Bool { return c == Color.red }
  > print(isRed(Color.green))
  > EOF
  $ ./lab.exe --emit-sil fn.swift | sed -n '/sil @isRed/,/^}/p'
  sil @isRed(%0 : $Color) -> $Bool {
  bb0:
    %1 = alloc_stack $Color  // c
    store %0 to %1
    %3 = load %1 $Color
    %4 = enum #0 () $Color
    %5 = enum_tag %3
    %6 = enum_tag %4
    %7 = binop "==" %5, %6 $Bool
    return %7
  }
