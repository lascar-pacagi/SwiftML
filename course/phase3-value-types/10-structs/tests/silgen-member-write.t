The second silgen hole, TODO(10): a member WRITE `p.x = e` takes the field's ADDRESS inside
p's own slot (`struct_element_addr`) and stores through it. `--emit-sil` stops after SILGen.
No program here reads a field (that is the first hole), so this file can go green on its own.

`p.x = 9` on `var p` is `struct_element_addr %slot, #0` followed by a `store` into it:

  $ cat > write.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 1, y: 2)
  > p.x = 9
  > EOF
  $ ./lab.exe --emit-sil write.swift
  struct Point { x: Int; y: Int }
  
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 1
    %1 = integer_literal $Int, 2
    %2 = struct (%0, %1) $Point
    %3 = alloc_stack $Point  // p
    store %2 to %3
    %5 = integer_literal $Int, 9
    %6 = struct_element_addr %3, #0
    store %5 to %6
    return
  }

`p.y = 5 * 2` addresses field #1; the value is generated BEFORE the address is taken:

  $ cat > y.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 1, y: 2)
  > p.y = 5 * 2
  > EOF
  $ ./lab.exe --emit-sil y.swift | grep -E 'integer_literal|struct_element_addr|store'
    %0 = integer_literal $Int, 1
    %1 = integer_literal $Int, 2
    store %2 to %3
    %5 = integer_literal $Int, 5
    %6 = integer_literal $Int, 2
    %8 = struct_element_addr %3, #1
    store %7 to %8

Two writes to the same variable both address the SAME slot (`%3`), each with its own index:

  $ cat > twice.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 1, y: 2)
  > p.x = 10
  > p.y = 20
  > EOF
  $ ./lab.exe --emit-sil twice.swift | grep struct_element_addr
    %6 = struct_element_addr %3, #0
    %9 = struct_element_addr %3, #1

Value semantics in the SIL: after `var q = p`, `q.x = 99` addresses q's slot (`%6`), not p's
(`%3`) — the copy has its own storage, so the write can never reach p:

  $ cat > copy.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 1, y: 2)
  > var q = p
  > q.x = 99
  > EOF
  $ ./lab.exe --emit-sil copy.swift | grep -E 'alloc_stack|struct_element_addr'
    %3 = alloc_stack $Point  // p
    %6 = alloc_stack $Point  // q
    %9 = struct_element_addr %6, #0

A Bool field is addressed as field `#1` and stored through that address like any other:

  $ cat > flag.swift <<'EOF'
  > struct Cell {
  >   var n: Int
  >   var alive: Bool
  > }
  > var c = Cell(n: 0, alive: false)
  > c.alive = true
  > EOF
  $ ./lab.exe --emit-sil flag.swift | grep -E 'struct_element_addr|store'
    store %2 to %3
    %6 = struct_element_addr %3, #1
    store %5 to %6

A write inside a loop body lands in that body's block, addressing the slot from `bb0`:

  $ cat > loop.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 0, y: 0)
  > var i = 0
  > while i < 3 {
  >   p.x = i
  >   i = i + 1
  > }
  > EOF
  $ ./lab.exe --emit-sil loop.swift | grep -E '^bb|struct_element_addr'
  bb0:
  bb1:
  bb2:
    %12 = struct_element_addr %3, #0
  bb3:
