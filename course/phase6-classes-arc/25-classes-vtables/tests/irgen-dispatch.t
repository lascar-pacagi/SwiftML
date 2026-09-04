TODO(25c) — the dispatch EMISSION, in `irgen.ml`: three loads and a call. Everything in this
file needs the other two holes as well; what it observes is the LLVM and, finally, the answer
a running program prints.

The three loads: word 0 of the object is its vtable, `getelementptr ptr` indexes the slot, and
the loaded pointer is called with the object as argument 0. Slot #0 and slot #1 differ only in
the index:

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
  $ ./lab.exe --emit-llvm v.swift | sed -n '/define i32 @main/,/^}/p' | grep -E 'getelementptr ptr|call i64 %'
    %t3 = getelementptr ptr, ptr %t2, i64 0
    %v9 = call i64 %t4(ptr %v8)
    %t6 = getelementptr ptr, ptr %t5, i64 1
    %v12 = call i64 %t7(ptr %v11)

The tables themselves are module-level constants, one array of function pointers per class,
and `Dog`'s is `Animal`'s with slot 0 replaced and one entry appended:

  $ ./lab.exe --emit-llvm v.swift | grep '^@vtbl'
  @vtbl.Animal = private unnamed_addr constant [2 x ptr] [ptr @Animal.sound, ptr @Animal.describe]
  @vtbl.Dog = private unnamed_addr constant [3 x ptr] [ptr @Dog.sound, ptr @Animal.describe, ptr @Dog.fetch]

A running program: dispatch through a superclass-typed variable answers 7, and `describe`'s
internal `sound()` answers 407 — the same numbers at `-Onone` and at `-O`:

  $ ./lab.exe build v.swift -o v && ./v
  7
  407
  $ ./lab.exe build v.swift -O -o vO && ./vO
  7
  407

Reference semantics — two bindings are one object, so `d.bump()` is visible through `c`, and
a field written through `c` is visible through `d`:

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

A VOID method is emitted as a bare `call void` through the loaded pointer — no result to name:

  $ ./lab.exe --emit-llvm ref.swift | grep -c 'call void %'
  2

`super.init` chains, initializer inheritance and a three-level hierarchy all run:

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

A subclass that adds no stored properties INHERITS its superclass's initializer, and the
implicit `super.init()` runs when the superclass's initializer takes no arguments:

  $ cat > inh.swift <<'SWIFT'
  > class A {
  >   var x: Int
  >   init() { x = 5 }
  >   func f() -> Int { return x }
  > }
  > class B: A { override func f() -> Int { return x * 2 } }
  > class D: A {
  >   var y: Int
  >   init(_ w: Int) { y = w }
  >   override func f() -> Int { return x + y }
  > }
  > print(B().f())
  > print(D(3).f())
  > SWIFT
  $ ./lab.exe build inh.swift -o inh && ./inh
  10
  8
