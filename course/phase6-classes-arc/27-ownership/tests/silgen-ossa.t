The OSSA recast in `silgen.ml` is GIVEN code — concept 26's raw `retain`/`release` restated as
structured operations. It has no hole of its own, but it cannot be read until `TODO(27)` exists
(the driver verifies before it emits), so this file reads TODO on the untouched skeleton along
with everything else. Its job is to pin the SHAPE the verifier is checking.

Three instructions replace two. A borrow that becomes an owner is `copy_value`; a slot giving
up its `+1` is `load [take]`, which moves the ownership out for free; and consuming it is
`destroy_value`. No `retain` or `release` survives.

  $ cat > o.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  > }
  > func f() {
  >   let a = T(1)
  >   let c = a
  >   print(c.id)
  > }
  > f()
  > SWIFT
  $ ./lab.exe --emit-sil o.swift | sed -n '/sil @f/,/^}/p' | grep -E 'copy_value|load \[take\]|destroy_value'
    %7 = copy_value %6
    %14 = load [take] %8 $T
    destroy_value %14
    %16 = load [take] %4 $T
    destroy_value %16
  $ ./lab.exe --emit-sil o.swift | grep -cE '^  (retain|release)' || true
  0

`load [take]` is the elegant half: a scope exit does not borrow the slot's value and then
release a borrow — it TAKES the `+1` out and destroys that. So the two appear in pairs, one per
slot, and the borrow that made the second owner is one `copy_value`:

  $ ./lab.exe --emit-sil o.swift | grep -c 'copy_value' || true
  1
  $ ./lab.exe --emit-sil o.swift | grep -c 'load \[take\]' || true
  2
  $ ./lab.exe --emit-sil o.swift | grep -c 'destroy_value' || true
  2

Class-typed PARAMETERS are guaranteed, and concept 27 stopped spilling them: `self` and a class
argument stay pure SSA values with no `alloc_stack` and no entry store. That is not a tidiness
choice — the entry store would have CONSUMED a borrow, which is exactly rule R2, and the
verifier reported it on its very first run:

  $ cat > p.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   func get() -> Int { return id }
  > }
  > func use(_ t: T) -> Int { return t.id }
  > func f() { let a = T(3)
  >   print(use(a) + a.get()) }
  > f()
  > SWIFT
  $ ./lab.exe --emit-sil p.swift | sed -n '/sil @use/,/^}/p'
  sil @use(%0 : $T) -> $Int {
  bb0:
    %1 = ref_element_addr %0, #0
    %2 = load %1 $Int
    return %2
  }
  $ ./lab.exe --emit-sil p.swift | sed -n '/sil @T.get/,/^}/p'
  sil @T.get(%0 : $T) -> $Int {
  bb0:
    %1 = ref_element_addr %0, #0
    %2 = load %1 $Int
    return %2
  }

An `Int` parameter beside a class one still gets its slot — only the MANAGED parameters are
kept in registers, because only they have ownership to lose:

  $ ./lab.exe --emit-sil p.swift | sed -n '/sil @T.init/,/^}/p'
  sil @T.init(%0 : $T, %1 : $Int) -> $() {
  bb0:
    %2 = alloc_stack $Int  // i
    store %1 to %2
    %4 = load %2 $Int
    %5 = ref_element_addr %0, #0
    store %4 to %5
    return
  }

The recast is behaviour-preserving: the concept-26 deinit orders are unchanged, at `-Onone` and
at `-O`.

  $ cat > life.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func g() {
  >   let a = T(1)
  >   let b = T(2)
  >   let c = a
  >   print(a.id + b.id + c.id)
  > }
  > g()
  > var v = T(4)
  > v = T(5)
  > print(9)
  > SWIFT
  $ ./lab.exe build life.swift -o life && ./life
  4
  2
  1
  4
  9
  $ ./lab.exe build life.swift -O -o lifeO && ./lifeO
  4
  2
  1
  4
  9

A field written through `self` lowers through the same ownership path as one written through a
binding — and it must not go looking for a slot named `self`, because there is not one any more
(that lookup is what used to crash the compiler here):

  $ cat > selffld.swift <<'SWIFT'
  > class L {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > class Box {
  >   var l: L
  >   var n: Int
  >   init(_ x: L) { self.l = x
  >     self.n = 0 }
  >   func put(_ x: L) { self.l = x
  >     self.n = self.n + 1 }
  > }
  > func f() {
  >   let b = Box(L(1))
  >   b.put(L(2))
  >   print(b.n)
  > }
  > f()
  > print(9)
  > SWIFT
  $ ./lab.exe --emit-sil selffld.swift | sed -n '/sil @Box.put/,/^}/p' | grep -E 'copy_value|load \[take\]|destroy_value|ref_element_addr'
    %2 = ref_element_addr %0, #0
    %3 = copy_value %1
    %4 = load [take] %2 $L
    destroy_value %4
    %7 = ref_element_addr %0, #1
    %11 = ref_element_addr %0, #1
  $ ./lab.exe build selffld.swift -o selffld && ./selffld
  1
  1
  2
  9
