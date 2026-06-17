Specialization + devirtualization (Milestone M5): `-O` erases the protocol/generic abstraction.
RED until the TODO(24) holes (the devirt folds + the call-site specializer).

A generic call specializes to a monomorphic clone; an existential method call on a known wrap
devirtualizes — and after inlining + GVN the optimized main has NO dispatch at all:

  $ cat > s.swift <<'SWIFT'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > func dbl<T: P>(_ t: T) -> Int { return t.v() + t.v() }
  > let s: P = A(x: 21)
  > print(s.v())
  > print(dbl(A(x: 10)))
  > SWIFT
  $ ./lab.exe --sil-opt s.swift | grep -c 'sil @dbl\$A'
  1
  $ ./lab.exe --sil-opt s.swift | grep -c 'witness_method' || true
  0
  $ ./lab.exe --sil-opt s.swift | grep -c 'init_existential' || true
  0
  $ ./lab.exe build s.swift -O -o s && ./s
  21
  20

Two concrete types get two clones; recursion specializes to a self-recursive clone:

  $ cat > t.swift <<'SWIFT'
  > protocol P { func v() -> Int }
  > struct A: P { var x: Int
  >   func v() -> Int { return x } }
  > struct B: P { func v() -> Int { return 100 } }
  > func g<T: P>(_ t: T) -> Int { return t.v() * 2 }
  > func rep<T: P>(_ t: T, _ n: Int) -> Int {
  >   if n == 0 { return 0 }
  >   return t.v() + rep(t, n - 1)
  > }
  > print(g(A(x: 3)) + g(B()))
  > print(rep(A(x: 5), 4))
  > SWIFT
  $ ./lab.exe --sil-opt t.swift | grep -oE 'sil @(g|rep)\$[A-Z]' | sort | uniq -c | sed 's/^ *//'
  1 sil @g$A
  1 sil @g$B
  1 sil @rep$A
  $ ./lab.exe build t.swift -O -o t && ./t
  206
  20

An UNPROVABLE existential stays on the erased path — both worlds coexist (like swiftc):

  $ cat > u.swift <<'SWIFT'
  > protocol P { func v() -> Int }
  > struct A: P { var x: Int
  >   func v() -> Int { return x } }
  > struct B: P { func v() -> Int { return 7 } }
  > func h(_ e: P) -> Int { return e.v() }
  > var e: P = A(x: 1)
  > if 1 < 2 { e = B() }
  > print(h(e))
  > SWIFT
  $ ./lab.exe build u.swift -O -o u && ./u
  7
