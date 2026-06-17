Generic functions: type parameters with protocol constraints, inferred at the call site,
compiled ONCE via erasure. RED until the TODO(22) holes (sema inference + call lowering).

The unspecialized lowering is visible in SIL — one copy of the function, T erased to its
constraint's existential, the T-result opened back to the concrete type at the call:

  $ cat > g.swift <<'SWIFT'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > func pick<T: P>(_ a: T, _ b: T) -> T {
  >   if a.v() > b.v() { return a }
  >   return b
  > }
  > let w = pick(A(x: 3), A(x: 8))
  > print(w.v())
  > print(w.x)
  > SWIFT
  $ ./lab.exe --emit-sil g.swift | grep -c 'sil @pick'
  1
  $ ./lab.exe --emit-sil g.swift | grep -E 'open_existential' | head -1
    %8 = open_existential %7 : $A
  $ ./lab.exe build g.swift -o g && ./g
  8
  8
  $ ./lab.exe build g.swift -O -o gO && ./gO
  8
  8

A generic calling a generic stays erased (no open in between); a where-clause is the same
constraint, spelled differently:

  $ cat > h.swift <<'SWIFT'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > struct B: P { func v() -> Int { return 2 } }
  > func one<T: P>(_ t: T) -> Int { return t.v() }
  > func both<T>(_ a: T, _ b: T) -> Int where T: P { return one(a) + one(b) }
  > print(both(A(), A()) + both(B(), B()))
  > SWIFT
  $ ./lab.exe build h.swift -o h && ./h
  6

Inference failures match swiftc:

  $ cat > c1.swift <<'SWIFT'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > struct B: P { func v() -> Int { return 2 } }
  > func f<T: P>(_ a: T, _ b: T) -> Int { return a.v() + b.v() }
  > print(f(A(), B()))
  > SWIFT
  $ ./lab.exe --typecheck c1.swift 2>&1 | head -1
  5:7: error: conflicting arguments to generic parameter 'T' ('A' vs. 'B')

  $ cat > c2.swift <<'SWIFT'
  > protocol P { func v() -> Int }
  > struct A { var x: Int }
  > func f<T: P>(_ a: T) -> Int { return a.v() }
  > print(f(A(x: 1)))
  > SWIFT
  $ ./lab.exe --typecheck c2.swift 2>&1 | head -1
  4:7: error: global function 'f' requires that 'A' conform to 'P'

  $ cat > c3.swift <<'SWIFT'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 }
  >   func w() -> Int { return 9 } }
  > func f<T: P>(_ a: T) -> Int { return a.w() }
  > print(f(A()))
  > SWIFT
  $ ./lab.exe --typecheck c3.swift 2>&1 | head -1
  4:38: error: value of type 'T' has no member 'w'
