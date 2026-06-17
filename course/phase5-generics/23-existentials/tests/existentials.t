Existential containers: the fixed 3-word buffer + heap boxing, and dynamic casts. RED until
the TODO(23) holes (silgen as?/as!; irgen inline-or-box).

A LARGE conformer (5 words > the 3-word buffer) is heap-boxed — and everything still works,
through functions, reassignment, casts, and -O:

  $ cat > big.swift <<'SWIFT'
  > protocol P { func v() -> Int }
  > struct Big: P {
  >   var a: Int
  >   var b: Int
  >   var c: Int
  >   var d: Int
  >   var e: Int
  >   func v() -> Int { return a + b + c + d + e }
  > }
  > struct Tiny: P { func v() -> Int { return 100 } }
  > func total(_ x: P, _ y: P) -> Int { return x.v() + y.v() }
  > var p: P = Big(a: 1, b: 2, c: 3, d: 4, e: 5)
  > print(total(p, Tiny()))
  > if let bb = p as? Big { print(bb.e) }
  > p = Tiny()
  > print(p.v())
  > SWIFT
  $ ./lab.exe build big.swift -o big && ./big
  115
  5
  100
  $ ./lab.exe build big.swift -O -o bigO && ./bigO
  115
  5
  100

`as?` succeeds and fails by the VALUE's type, not the static type; an unrelated cast is
always-nil (and warned, like swiftc):

  $ cat > cast.swift <<'SWIFT'
  > protocol P { func v() -> Int }
  > struct A: P { var x: Int
  >   func v() -> Int { return x } }
  > struct B: P { func v() -> Int { return -5 } }
  > struct C { var z: Int }
  > let p: P = A(x: 7)
  > if let a = p as? A { print(a.x) }
  > if let b = p as? B { print(b.v()) } else { print(-1) }
  > if let c = p as? C { print(c.z) } else { print(-2) }
  > SWIFT
  $ ./lab.exe --typecheck cast.swift 2>&1 | head -1
  9:12: warning: cast from 'any P' to unrelated type 'C' always fails
  $ ./lab.exe build cast.swift -o cast && ./cast
  7
  -1
  -2

`as!` aborts on mismatch with swiftc's exit code (134 = SIGABRT; the wrapper shell keeps the
nondeterministic job message out of the transcript):

  $ cat > bang.swift <<'SWIFT'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > struct B: P { func v() -> Int { return 2 } }
  > let x: P = A()
  > let ok = x as! A
  > print(ok.v())
  > let y = x as! B
  > print(y.v())
  > SWIFT
  $ ./lab.exe build bang.swift -o bang
  $ sh -c './bang; echo "exit=$?"' 2>/dev/null
  1
  exit=134

The SIL shows the identity test and the cast diamond:

  $ ./lab.exe --emit-sil cast.swift | grep -c 'same_witness'
  2
