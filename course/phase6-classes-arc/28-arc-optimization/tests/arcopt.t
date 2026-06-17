ARC optimization (Milestone M6): provably-redundant copy/destroy pairs disappear under -O —
without moving a single deinit. RED until TODO(28) (the copy-propagation rewrite).

A borrow-copy of a parameter is pure overhead — the pass deletes the whole bracket:

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
  $ ./lab.exe --emit-sil cp.swift | grep -c 'copy_value'
  1
  $ ./lab.exe --sil-opt cp.swift | grep -c 'copy_value' || true
  0

Chained copies cascade away (one rewrite per sweep, to a fixpoint):

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
  $ ./lab.exe --emit-sil chain.swift | grep -c 'copy_value'
  3
  $ ./lab.exe --sil-opt chain.swift | grep -c 'copy_value' || true
  0
  $ ./lab.exe build chain.swift -O -o chain && ./chain
  11

DEINIT TIMING IS UNTOUCHED — the deletable pair never moved a lifetime, and the
NON-deletable one (a load-sourced copy whose slot is overwritten inside the bracket — the
copy is what keeps the old object alive) is correctly kept:

  $ cat > keep.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func f() {
  >   let a = T(1)
  >   let c = a
  >   print(c.id * 10)
  > }
  > f()
  > var x = T(3)
  > let keep = x
  > x = T(4)
  > print(keep.id * 100)
  > print(9)
  > SWIFT
  $ ./lab.exe build keep.swift -o k0 && ./k0
  10
  1
  300
  9
  $ ./lab.exe build keep.swift -O -o kO && ./kO
  10
  1
  300
  9

Whole-module devirtualization: a subclass-FREE class's dispatch becomes a direct call (and
inlines); an overridden hierarchy keeps its vtable dispatch:

  $ ./lab.exe --sil-opt cp.swift | grep -c 'class_method' || true
  0
  $ cat > sub.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1 }
  >   func f() -> Int { return 1 } }
  > class B: A { override func f() -> Int { return 2 } }
  > func go(_ a: A) -> Int { return a.f() }
  > print(go(B()))
  > SWIFT
  $ ./lab.exe --sil-opt sub.swift | grep -c 'class_method'
  1
  $ ./lab.exe build sub.swift -O -o sub && ./sub
  2
