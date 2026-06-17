Classes: reference semantics, init, inheritance, override, VTABLE dispatch. RED until the
TODO(25) holes (sema vtable build; silgen dispatch; irgen dispatch emission).

Reference semantics — two bindings, one object:

  $ cat > ref.swift <<'SWIFT'
  > class Counter {
  >   var n: Int
  >   init(_ start: Int) { n = start }
  >   func bump() { n = n + 1 }
  >   func value() -> Int { return n }
  > }
  > let c = Counter(10)
  > let d = c
  > d.bump()
  > c.bump()
  > print(c.value())
  > c.n = 50
  > print(d.value())
  > SWIFT
  $ ./lab.exe build ref.swift -o ref && ./ref
  12
  50

The vtable in SIL — slots inherited, the override REPLACES in place, new methods append:

  $ cat > v.swift <<'SWIFT'
  > class Animal {
  >   var legs: Int
  >   init(_ l: Int) { legs = l }
  >   func sound() -> Int { return 0 }
  >   func describe() -> Int { return legs * 100 + sound() }
  > }
  > class Dog: Animal {
  >   override func sound() -> Int { return 7 }
  >   func fetch() -> Int { return 1 }
  > }
  > let a: Animal = Dog(4)
  > print(a.sound())
  > print(a.describe())
  > SWIFT
  $ ./lab.exe --emit-sil v.swift | grep -A4 'sil_vtable Dog'
  sil_vtable Dog {
    #0: @Dog.sound
    #1: @Animal.describe
    #2: @Dog.fetch
  }

Dynamic dispatch through a SUPERCLASS-typed variable — and through the superclass's own
methods (`describe` calls `sound()` and the override wins):

  $ ./lab.exe build v.swift -o v && ./v
  7
  407
  $ ./lab.exe build v.swift -O -o vO && ./vO
  7
  407

super.init chains; inherited initializers; deep hierarchies:

  $ cat > h.swift <<'SWIFT'
  > class A {
  >   var x: Int
  >   init(_ v: Int) { x = v }
  >   func f() -> Int { return 1 }
  > }
  > class B: A {
  >   var y: Int
  >   init(_ v: Int, _ w: Int) { y = w
  >     super.init(v) }
  >   override func f() -> Int { return x + y }
  > }
  > class C: B { override func f() -> Int { return x * y } }
  > print(B(3, 4).f())
  > let a: A = C(5, 6)
  > print(a.f())
  > SWIFT
  $ ./lab.exe build h.swift -o h && ./h
  7
  30

The class-shape diagnostics match swiftc:

  $ printf 'class C { var x: Int }\n' > c1.swift
  $ ./lab.exe --typecheck c1.swift 2>&1 | head -1
  1:1: error: class 'C' has no initializers

  $ cat > c2.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1 }
  >   func f() -> Int { return 1 } }
  > class B: A { func f() -> Int { return 2 } }
  > SWIFT
  $ ./lab.exe --typecheck c2.swift 2>&1 | head -1
  4:14: error: overriding declaration requires an 'override' keyword

  $ cat > c3.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1 } }
  > class B: A { override func f() -> Int { return 2 } }
  > SWIFT
  $ ./lab.exe --typecheck c3.swift 2>&1 | head -1
  3:23: error: method does not override any method from its superclass

  $ cat > c4.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1 } }
  > class B: A { var y: Int
  >   init() { y = 2 } }
  > SWIFT
  $ ./lab.exe --typecheck c4.swift 2>&1 | head -1
  4:3: error: 'super.init' isn't called on all paths before returning from initializer
