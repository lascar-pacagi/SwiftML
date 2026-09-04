TODO(25b) — the dispatch lowering, in `silgen.ml`. A method call on a class receiver becomes
`class_method %recv, #slot ; apply(args)`: the SLOT comes from the receiver's STATIC type, the
table comes from the object at run time. `--emit-sil` stops before IRGen, so this file reads
the lowering without needing TODO(25c).

Through an `Animal`-typed variable, `sound()` is slot #0 and `describe()` slot #1.
Those are the numbers `Animal` fixed — a `Dog` behind the variable changes nothing about them:

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
  $ ./lab.exe --emit-sil v.swift | sed -n '/sil @main/,/^}/p' | grep class_method
    %9 = class_method %8, #0 ; apply() $Int
    %12 = class_method %11, #1 ; apply() $Int

The superclass's own body dispatches too: `describe` calls `sound()` on `self`, and that bare
self-call is slot #0 through the vtable, not a direct call to `@Animal.sound` — which is the
whole reason a `Dog` answers 7:

  $ ./lab.exe --emit-sil v.swift | sed -n '/sil @Animal.describe/,/^}/p' | grep -E 'class_method|function_ref'
    %9 = class_method %8, #0 ; apply() $Int

A method that only the subclass has is dispatched at the slot the subclass appended, #2, and
it is reached through a `Dog`-typed receiver:

  $ cat > f.swift <<'SWIFT'
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
  > let d = Dog(4)
  > print(d.fetch())
  > SWIFT
  $ ./lab.exe --emit-sil f.swift | sed -n '/sil @main/,/^}/p' | grep class_method
    %8 = class_method %7, #2 ; apply() $Int

A VOID method dispatches through the same instruction with no result type printed:

  $ cat > vd.swift <<'SWIFT'
  > class C {
  >   var n: Int
  >   init() { n = 0 }
  >   func bump() { n = n + 1 }
  > }
  > let c = C()
  > c.bump()
  > print(c.n)
  > SWIFT
  $ ./lab.exe --emit-sil vd.swift | sed -n '/sil @main/,/^}/p' | grep class_method
    %6 = class_method %5, #0 ; apply() $()

Arguments go through the callee's declared parameter types, so an `Int` literal passed where
the method wants `Int?` is wrapped into `.some` at the call site, not stored raw:

  $ cat > ar.swift <<'SWIFT'
  > class Box {
  >   var v: Int
  >   init() { v = 0 }
  >   func put(_ x: Int?) -> Int { if let y = x { return y }
  >     return -1 }
  > }
  > let b = Box()
  > print(b.put(5))
  > SWIFT
  $ ./lab.exe --emit-sil ar.swift | sed -n '/sil @main/,/^}/p' | grep -E 'enum|class_method'
    %7 = enum #1 (%6) $Int?
    %8 = class_method %5, #0 ; apply(%7) $Int

The boundary: a STRUCT method is not dispatch at all. It stays a direct `apply` of a
`function_ref` — value types have no vtable to look in:

  $ cat > st.swift <<'SWIFT'
  > struct P {
  >   var x: Int
  >   func get() -> Int { return x }
  > }
  > print(P(x: 4).get())
  > SWIFT
  $ ./lab.exe --emit-sil st.swift | sed -n '/sil @main/,/^}/p' | grep -cE 'class_method' || true
  0
  $ ./lab.exe --emit-sil st.swift | sed -n '/sil @main/,/^}/p' | grep -c 'function_ref @P.get'
  1

`super.init` is the one class call that is deliberately STATIC: a direct `apply` of
`@Animal.init` on an upcast self, because there is nothing to choose:

  $ cat > si.swift <<'SWIFT'
  > class A { var x: Int
  >   init(_ v: Int) { x = v } }
  > class B: A { var y: Int
  >   init(_ v: Int, _ w: Int) { y = w
  >     super.init(v) } }
  > print(B(3, 4).y)
  > SWIFT
  $ ./lab.exe --emit-sil si.swift | sed -n '/sil @B.init/,/^}/p' | grep -E 'upcast|function_ref|class_method'
    %15 = upcast %13 : $A
    %16 = function_ref @A.init
