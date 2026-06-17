The ARC runtime: deinit TIMING AND ORDER must match swiftc exactly — that is Milestone M6's
oracle. RED until the TODO(26) holes (ownership transfer; destructor tail; rt.release).

Scope exit, reverse declaration order, and exactly-once for shared objects:

  $ cat > scope.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func f() {
  >   let a = T(1)
  >   let b = T(2)
  >   let c = a
  >   print(a.id + b.id + c.id)
  > }
  > f()
  > print(9)
  > SWIFT
  $ ./lab.exe build scope.swift -o scope && ./scope
  4
  2
  1
  9

Reassignment: the new object is built BEFORE the old one dies; top-level vars never deinit
(they are globals — swiftc never runs deinit at process exit):

  $ cat > re.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i
  >     print(id * 10) }
  >   deinit { print(id * 10 + 1) }
  > }
  > var v = T(2)
  > v = T(3)
  > print(300)
  > SWIFT
  $ ./lab.exe build re.swift -o re && ./re
  20
  30
  21
  300

The deallocation order is subtle and swiftc-verified: ALL deinit BODIES run derived -> base
FIRST, and only then do the class-typed fields release (base-level fields before derived):

  $ cat > chain.swift <<'SWIFT'
  > class Leaf {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > class A {
  >   var x: Int
  >   init(_ v: Int) { x = v }
  >   deinit { print(1000 + x) }
  > }
  > class B: A {
  >   var l: Leaf
  >   init(_ v: Int, _ l0: Leaf) { l = l0
  >     super.init(v) }
  >   deinit { print(2000) }
  > }
  > func go() {
  >   let b = B(3, Leaf(7))
  >   print(b.x)
  > }
  > go()
  > print(0)
  > SWIFT
  $ ./lab.exe build chain.swift -o chain && ./chain
  3
  2000
  1003
  7
  0

Ownership transfers through returns; loop iterations release their locals; -O preserves all
of it (retain/release are SIDE-EFFECTING — no pass may drop or reorder them):

  $ cat > own.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func mk() -> T { let t = T(6)
  >   return t }
  > func g() {
  >   let t = mk()
  >   print(t.id * 2)
  > }
  > g()
  > for i in 0 ..< 2 {
  >   let t = T(i + 10)
  >   print(t.id * 100)
  > }
  > print(5)
  > SWIFT
  $ ./lab.exe build own.swift -o own && ./own
  12
  6
  1000
  10
  1100
  11
  5
  $ ./lab.exe build own.swift -O -o ownO && ./ownO
  12
  6
  1000
  10
  1100
  11
  5

The v0 guards reject class references inside value types (bitwise copies would corrupt the
count — the honest boundary until copy machinery exists):

  $ printf 'class K { var x: Int\n  init() { x = 1 } }\nstruct S { var k: K }\n' > g1.swift
  $ ./lab.exe --typecheck g1.swift 2>&1 | head -1
  3:1: error: class references inside structs are not supported in this subset
