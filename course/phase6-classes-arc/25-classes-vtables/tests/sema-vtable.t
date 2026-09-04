TODO(25a) — the vtable build, in `sema.ml`. A class's method table starts as its superclass's,
an `override` replaces its slot IN PLACE, and a new method appends; the same walk is where the
two override diagnostics come from. `--emit-sil` prints the tables it produced, and
`--typecheck` stops before any lowering, so nothing here needs the other two holes.

`Dog`'s table inherits `Animal`'s slot numbering: the override sits in #0, the
inherited `describe` stays in #1, and the new `fetch` appends as #2.

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
  > print(a.legs)
  > SWIFT
  $ ./lab.exe --emit-sil v.swift | sed -n '/sil_vtable Animal/,/^}/p'
  sil_vtable Animal {
    #0: @Animal.sound
    #1: @Animal.describe
  }
  $ ./lab.exe --emit-sil v.swift | sed -n '/sil_vtable Dog/,/^}/p'
  sil_vtable Dog {
    #0: @Dog.sound
    #1: @Animal.describe
    #2: @Dog.fetch
  }

A three-level chain keeps ONE numbering all the way down: `Cub` overrides `sound` again, so
slot #0 changes function for a third time while #1 and #2 are untouched.

  $ cat > deep.swift <<'SWIFT'
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
  > class Cub: Dog {
  >   override func sound() -> Int { return 3 }
  >   override func fetch() -> Int { return 2 }
  > }
  > let c = Cub(4)
  > print(c.legs)
  > SWIFT
  $ ./lab.exe --emit-sil deep.swift | sed -n '/sil_vtable Cub/,/^}/p'
  sil_vtable Cub {
    #0: @Cub.sound
    #1: @Animal.describe
    #2: @Cub.fetch
  }

A class with no superclass numbers its own methods from #0, in declaration order:

  $ cat > flat.swift <<'SWIFT'
  > class Counter {
  >   var n: Int
  >   init(_ s: Int) { n = s }
  >   func value() -> Int { return n }
  >   func doubled() -> Int { return n + n }
  > }
  > let k = Counter(3)
  > print(k.n)
  > SWIFT
  $ ./lab.exe --emit-sil flat.swift | sed -n '/sil_vtable Counter/,/^}/p'
  sil_vtable Counter {
    #0: @Counter.value
    #1: @Counter.doubled
  }

Redefining a superclass method without saying `override` is swiftc's
`overriding declaration requires an 'override' keyword`:

  $ cat > c2.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1 }
  >   func f() -> Int { return 1 } }
  > class B: A { func f() -> Int { return 2 } }
  > SWIFT
  $ ./lab.exe --typecheck c2.swift; echo "exit=$?"
  4:14: error: overriding declaration requires an 'override' keyword
  exit=1

Saying `override` when the superclass has no such method is the opposite error,
`method does not override any method from its superclass`:

  $ cat > c3.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1 } }
  > class B: A { override func f() -> Int { return 2 } }
  > SWIFT
  $ ./lab.exe --typecheck c3.swift; echo "exit=$?"
  3:23: error: method does not override any method from its superclass
  exit=1

A name that matches but a SIGNATURE that does not is not an override either — there is no slot
to replace, so it is the same diagnostic (swiftc agrees, for the same reason):

  $ cat > c5.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1 }
  >   func f() -> Int { return 1 } }
  > class B: A { override func f() -> Bool { return true } }
  > class C: A { override func f(_ n: Int) -> Int { return n } }
  > SWIFT
  $ ./lab.exe --typecheck c5.swift; echo "exit=$?"
  4:23: error: method does not override any method from its superclass
  5:23: error: method does not override any method from its superclass
  exit=1

A method a class merely INHERITS is still overridable two levels down, and overriding it there
is not the "does not override" error — the slot exists, it just came from a grandparent:

  $ cat > c6.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1 }
  >   func f() -> Int { return 1 } }
  > class B: A { }
  > class C: B { override func f() -> Int { return 3 } }
  > let c: A = C()
  > print(c.x)
  > SWIFT
  $ ./lab.exe --typecheck c6.swift; echo "exit=$?"
  exit=0
