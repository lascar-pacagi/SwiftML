TODO(28) — the copy-propagation rewrite, in `opt.ml`. A `copy_value` whose only consumer is a
`destroy_value` in the same block, all of whose uses sit inside that bracket, and whose SOURCE
is alive across it, is pure overhead: delete both and point the uses at the source.
`--emit-sil` shows the raw traffic, `--sil-opt` shows what survives.

A borrow-copy of a GUARANTEED parameter is the textbook case — the caller already holds the
object for the length of the call, so the bracket protects nothing:

  $ cat > cp.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  > }
  > func f(_ a: T) -> Int {
  >   let c = a
  >   return c.id
  > }
  > print(f(T(5)))
  > SWIFT
  $ ./lab.exe --emit-sil cp.swift | sed -n '/sil @f/,/^}/p' | grep -E 'copy_value|destroy_value'
    %1 = copy_value %0
    destroy_value %7
  $ ./lab.exe --sil-opt cp.swift | grep -c 'copy_value' || true
  0
  $ ./lab.exe build cp.swift -O -o cp && ./cp
  5

Chained copies CASCADE, but only one per sweep: deleting an instruction shifts every later
index and stales the use map, so the pass rewrites once and lets the fixpoint recompute. Three
copies still all disappear.

  $ cat > chain.swift <<'SWIFT'
  > class N {
  >   var v: Int
  >   init(_ v0: Int) { v = v0 }
  > }
  > func pass3(_ n: N) -> Int {
  >   let a = n
  >   let b = a
  >   let c = b
  >   return c.v
  > }
  > print(pass3(N(11)))
  > SWIFT
  $ ./lab.exe --emit-sil chain.swift | grep -c 'copy_value' || true
  3
  $ ./lab.exe --sil-opt chain.swift | grep -c 'copy_value' || true
  0
  $ ./lab.exe build chain.swift -O -o chain && ./chain
  11

A copy of an OWNED local is deletable too, as long as the source is consumed later in the same
block — the object is alive across the bracket either way:

  $ cat > loc.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func f() -> Int {
  >   let a = T(1)
  >   let c = a
  >   return c.id * 10
  > }
  > print(f())
  > print(9)
  > SWIFT
  $ ./lab.exe --sil-opt loc.swift | grep -c 'copy_value' || true
  0
  $ ./lab.exe build loc.swift -o loc && ./loc
  1
  10
  9
  $ ./lab.exe build loc.swift -O -o locO && ./locO
  1
  10
  9

THE KEEP CASE, and the reason condition three exists. Here the copy's source is a LOAD from a
slot that is OVERWRITTEN inside the bracket. Deleting the copy would drop the object's only
other `+1` and `T(1)` would die at the reassignment instead of at scope exit — keeping it alive
was the copy's whole job. The pass must leave it alone, and the printed order proves it:

  $ cat > keep.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func f() {
  >   var a = T(1)
  >   let c = a
  >   a = T(2)
  >   print(c.id * 10)
  >   print(a.id * 100)
  > }
  > f()
  > print(9)
  > SWIFT
  $ ./lab.exe --emit-sil keep.swift | grep -c 'copy_value' || true
  1
  $ ./lab.exe --sil-opt keep.swift | grep -c 'copy_value' || true
  1
  $ ./lab.exe build keep.swift -o k0 && ./k0
  10
  200
  1
  2
  9
  $ ./lab.exe build keep.swift -O -o kO && ./kO
  10
  200
  1
  2
  9

DEINIT TIMING IS UNTOUCHED — the whole point. Two locals dying in reverse order, a
reassignment, and a class-typed field replaced, all identical at `-Onone` and at `-O`:

  $ cat > life.swift <<'SWIFT'
  > class L {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > class Box {
  >   var l: L
  >   init(_ x: L) { l = x }
  >   func put(_ x: L) { l = x }
  > }
  > func g() {
  >   let a = L(1)
  >   let b = L(2)
  >   let c = a
  >   print(a.id + b.id + c.id)
  > }
  > g()
  > func h() {
  >   let bx = Box(L(10))
  >   bx.put(L(20))
  >   print(50)
  > }
  > h()
  > print(9)
  > SWIFT
  $ ./lab.exe build life.swift -o l0 && ./l0
  4
  2
  1
  10
  50
  20
  9
  $ ./lab.exe build life.swift -O -o lO && ./lO
  4
  2
  1
  10
  50
  20
  9

Whatever survives stays BALANCED. Every object in `keep.swift` is born from an `alloc_ref` or a
`copy_value` and dies at exactly one `destroy_value`, so those two counts must agree after the
pass has run — a rewrite that dropped a destroy without its copy shows up here as arithmetic
rather than as a crash three concepts later. (The identity is a per-object one, so it holds
whole-module only while no object is owned by a FIELD, whose destroy lives in a destructor
chain; `life.swift` above has one, which is why it is not the program used here.)

  $ ./lab.exe --sil-opt keep.swift | grep -c 'destroy_value' || true
  3
  $ ./lab.exe --sil-opt keep.swift | grep -cE 'copy_value|alloc_ref' || true
  3
