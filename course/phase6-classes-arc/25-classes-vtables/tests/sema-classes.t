The front-end rules around classes are GIVEN code — none of this file is a hole. It is here
because `oracle.t` is only a fair test while the corpus stays inside what swiftc and we mean the
same thing by, and this is where that boundary is written down. `--typecheck` stops after sema:
exit 0 and silence is "accepted".

It still reads FAIL, not PASS, on the untouched skeleton, and for a reason worth knowing: a
class that declares a METHOD cannot be laid out at all until `TODO(25a)` builds its vtable, so
the three cases below whose program needs a method go red with everything else. The cases with
no method in them are green from the first run.

A class that adds stored properties must be constructible — swiftc reports this at the class
NAME, and so do we:

  $ printf 'class C { var x: Int }\n' > c1.swift
  $ ./lab.exe --typecheck c1.swift; echo "exit=$?"
  1:7: error: class 'C' has no initializers
  exit=1

Definite initialization: every own stored property assigned before the initializer returns, and
`super.init` called when the superclass's initializer takes arguments. swiftc runs DI on SIL,
so `swiftc -typecheck` stays silent on both of these and only a full compile reports them —
ours fires in sema, same programs rejected, earlier (§2):

  $ cat > di.swift <<'SWIFT'
  > class A {
  >   var x: Int
  >   var z: Int
  >   init() { x = 1 }
  > }
  > SWIFT
  $ ./lab.exe --typecheck di.swift; echo "exit=$?"
  4:3: error: return from initializer without initializing all stored properties
  exit=1

  $ cat > c4.swift <<'SWIFT'
  > class A { var x: Int
  >   init(_ v: Int) { x = v } }
  > class B: A { var y: Int
  >   init() { y = 2 } }
  > SWIFT
  $ ./lab.exe --typecheck c4.swift; echo "exit=$?"
  4:3: error: 'super.init' isn't called on all paths before returning from initializer
  exit=1

`super` has three ways to be wrong, and swiftc has a different sentence for each: called twice,
used in a class with no superclass, and used outside an initializer.

  $ cat > s1.swift <<'SWIFT'
  > class A { var x: Int
  >   init(_ v: Int) { x = v } }
  > class B: A { var y: Int
  >   init() { y = 1
  >     super.init(1)
  >     super.init(2) } }
  > SWIFT
  $ ./lab.exe --typecheck s1.swift; echo "exit=$?"
  6:5: error: 'super.init' called multiple times in initializer
  exit=1

  $ cat > s2.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1
  >     super.init() } }
  > SWIFT
  $ ./lab.exe --typecheck s2.swift; echo "exit=$?"
  3:5: error: 'super' cannot be used in class 'A' because it has no superclass
  exit=1

  $ cat > s3.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1 } }
  > class B: A { func g() { super.init() } }
  > SWIFT
  $ ./lab.exe --typecheck s3.swift; echo "exit=$?"
  3:25: error: 'super.init' cannot be called outside of an initializer
  exit=1

An unknown superclass is reported once, at the class that named it, and does not take the rest
of the check down with it:

  $ printf 'class B: Nope { var y: Int\n  init() { y = 1 } }\n' > sup.swift
  $ ./lab.exe --typecheck sup.swift; echo "exit=$?"
  1:7: error: cannot find type 'Nope' in scope
  exit=1

A `let` stored property takes its value once, inside the initializer that owns it. Writing it
afterwards is refused — through a binding, or from a method — while the `var` beside it is
free. (`c` is a `let` BINDING and that is fine: the binding is constant, the object is not.)

  $ cat > lf.swift <<'SWIFT'
  > class C {
  >   let k: Int
  >   var n: Int
  >   init() { k = 1
  >     n = 2 }
  >   func bad() { k = 9 }
  > }
  > let c = C()
  > c.n = 5
  > c.k = 5
  > SWIFT
  $ ./lab.exe --typecheck lf.swift; echo "exit=$?"
  6:16: error: cannot assign to property: 'k' is a 'let' constant
  10:1: error: cannot assign to property: 'k' is a 'let' constant
  exit=1

The same rule for a struct's `let` property, which reaches this concept unchanged from
phase 5 — and a `let` BINDING freezes a struct's `var` properties too, because the whole value
is the constant:

  $ cat > lfs.swift <<'SWIFT'
  > struct S {
  >   let k: Int
  >   var n: Int
  > }
  > var s = S(k: 1, n: 2)
  > s.n = 5
  > s.k = 5
  > let t = S(k: 1, n: 2)
  > t.n = 5
  > SWIFT
  $ ./lab.exe --typecheck lfs.swift; echo "exit=$?"
  7:1: error: cannot assign to property: 'k' is a 'let' constant
  9:1: error: cannot assign to property: 't' is a 'let' constant
  exit=1

`print` lowers a scalar only, and `==` needs an Equatable conformance the back end could
compile — so an aggregate is refused up front rather than reaching IRGen. Both are honest
divergences: swiftc prints `main.C` for a class and rejects `==` on two of them in the same
words we use (§2). Class identity is `===`, an exercise.

  $ cat > agg.swift <<'SWIFT'
  > class C {
  >   var x: Int
  >   init() { x = 1 }
  > }
  > struct S { var x: Int }
  > enum E { case a }
  > let o: Int? = 5
  > print(C())
  > print(S(x: 1))
  > print(E.a)
  > print(o)
  > print(C() == C())
  > print(S(x: 1) == S(x: 2))
  > SWIFT
  $ ./lab.exe --typecheck agg.swift; echo "exit=$?"
  8:7: error: cannot print a value of type 'C' (only Int, Double, Bool and String)
  9:7: error: cannot print a value of type 'S' (only Int, Double, Bool and String)
  10:7: error: cannot print a value of type 'E' (only Int, Double, Bool and String)
  11:7: error: cannot print a value of type 'Int?' (only Int, Double, Bool and String)
  12:7: error: binary operator '==' cannot be applied to two 'C' operands
  13:7: error: binary operator '==' cannot be applied to two 'S' operands
  exit=1

An upcast is implicit and free; the other direction is not a conversion at all (downcasting
classes is an exercise), so it is a type error:

  $ cat > up.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1 } }
  > class B: A { }
  > let a: A = B()
  > print(a.x)
  > let b: B = A()
  > SWIFT
  $ ./lab.exe --typecheck up.swift; echo "exit=$?"
  6:12: error: cannot convert value of type 'A' to specified type 'B'
  exit=1

A method that is not in the receiver's STATIC type cannot be called on it, however the object
was made — the slot is chosen at compile time:

  $ cat > mem.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1 } }
  > class B: A { func fetch() -> Int { return 2 } }
  > let a: A = B()
  > print(a.fetch())
  > SWIFT
  $ ./lab.exe --typecheck mem.swift; echo "exit=$?"
  5:7: error: value of type 'A' has no member 'fetch'
  exit=1
