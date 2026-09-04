TODO(27) — `verify_ownership`, in `sil.ml`. The driver runs it on EVERY compile, before IRGen,
so until it exists nothing in this concept lowers at all and every file here reads TODO. What
it must do is classify each class-typed value as OWNED or GUARANTEED and then enforce three
rules: an owned value is consumed exactly once, a guaranteed one is never consumed, and nothing
is used after its consume.

Its success condition is SILENCE. Source code cannot express a violation — SILGen is the only
thing that writes this IR, and it is (now) correct — so the three rules are pinned by
hand-built bad SIL in `tests/test_ownership.ml`, and what this file checks is the other half:
that the verifier accepts everything the compiler really generates, and says so by not
speaking. A compile that printed `ownership error:` here would be the verifier accusing its own
SILGen.

The straight-line case: a fresh object, a copy, a borrow passed to a function, both slots taken
and destroyed at scope exit.

  $ cat > o.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  > }
  > func use(_ t: T) -> Int { return t.id }
  > func f() {
  >   let a = T(1)
  >   let c = a
  >   print(use(c))
  > }
  > f()
  > SWIFT
  $ ./lab.exe --emit-sil o.swift > /dev/null 2>ownerr.txt; echo "exit=$?"; cat ownerr.txt
  exit=0

Control flow, where "exactly once" is easiest to get wrong: a value born in a loop, an early
`return`, a `break` and a `continue` each abandoning an iteration's local.

  $ cat > cf.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func early(_ n: Int) -> Int {
  >   let a = T(n)
  >   if a.id > 2 { return a.id }
  >   return 0
  > }
  > func loops() {
  >   var i = 0
  >   while i < 4 {
  >     let t = T(i)
  >     i = i + 1
  >     if t.id == 1 { continue }
  >     if t.id == 2 { break }
  >     print(t.id)
  >   }
  > }
  > print(early(5))
  > loops()
  > SWIFT
  $ ./lab.exe --emit-sil cf.swift > /dev/null 2>ownerr.txt; echo "exit=$?"; cat ownerr.txt
  exit=0

Ownership that crosses a function boundary: a `+1` returned to the caller, a borrow passed in,
a class-typed field overwritten, and the two destructor chains — all of which the verifier sees
as ordinary functions and must accept.

  $ cat > cross.swift <<'SWIFT'
  > class L {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > class Box {
  >   var l: L
  >   init(_ x: L) { l = x }
  >   func put(_ x: L) { l = x }
  >   deinit { print(0) }
  > }
  > func mk(_ n: Int) -> L { let t = L(n)
  >   return t }
  > func f() {
  >   let b = Box(mk(1))
  >   b.put(mk(2))
  >   print(50)
  > }
  > f()
  > SWIFT
  $ ./lab.exe --emit-sil cross.swift > /dev/null 2>ownerr.txt; echo "exit=$?"; cat ownerr.txt
  exit=0

Inheritance, dispatch and `self`: an overridden method, a superclass method calling back into
the subclass, and a field written through `self` — the last of which used to crash the compiler
outright, because `self` has no slot to look up (`silgen-ossa.t` shows the shape).

  $ cat > inh.swift <<'SWIFT'
  > class A {
  >   var x: Int
  >   init(_ v: Int) { x = v }
  >   func f() -> Int { return 1 }
  >   func g() -> Int { return f() + 100 }
  >   func set(_ v: Int) { self.x = v }
  >   deinit { print(x) }
  > }
  > class B: A {
  >   var y: Int
  >   init(_ v: Int, _ w: Int) { y = w
  >     super.init(v) }
  >   override func f() -> Int { return y }
  >   deinit { print(y) }
  > }
  > func run() {
  >   let b: A = B(1, 2)
  >   b.set(7)
  >   print(b.g())
  > }
  > run()
  > SWIFT
  $ ./lab.exe --emit-sil inh.swift > /dev/null 2>ownerr.txt; echo "exit=$?"; cat ownerr.txt
  exit=0

And the same four programs all the way to a binary, at `-Onone` and at `-O`, because the
verifier runs before the optimizer on both paths:

  $ ./lab.exe build inh.swift -o inh && ./inh
  102
  2
  7
  $ ./lab.exe build inh.swift -O -o inhO && ./inhO
  102
  2
  7
  $ ./lab.exe build cross.swift -o cross && ./cross
  1
  50
  0
  2
