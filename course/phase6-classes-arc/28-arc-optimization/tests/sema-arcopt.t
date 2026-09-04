The boundary this concept has to stay inside is GIVEN code — no hole here. It is where the v0
guards live, and `oracle.t` is only a fair test while the corpus respects them. `--typecheck`
stops after sema: exit 0 and silence is "accepted".

It is green from the first run: the hole is an optimizer pass, and `--typecheck` stops long
before any SIL exists — let alone any `-O`.

A class reference inside a STRUCT is refused. A struct is copied bitwise, and a bitwise copy of
a reference makes a second owner the count never heard about — the honest boundary until copy
machinery exists (swiftc has it, and accepts this):

  $ printf 'class K { var x: Int\n  init() { x = 1 } }\nstruct S { var k: K }\n' > g1.swift
  $ ./lab.exe --typecheck g1.swift; echo "exit=$?"
  3:8: error: class references inside structs are not supported in this subset
  exit=1

The same for an enum payload and for an optional, the other two value containers — including
the annotated `let`, which used to slip past the check and miscompile (the slot held a class
reference the ARC insertion never saw, so the deinit ran on freed memory):

  $ cat > g2.swift <<'SWIFT'
  > class K { var x: Int
  >   init() { x = 1 } }
  > enum E { case some(K) }
  > SWIFT
  $ ./lab.exe --typecheck g2.swift; echo "exit=$?"
  3:6: error: class references inside enum payloads are not supported in this subset
  exit=1

  $ cat > g3.swift <<'SWIFT'
  > class K { var x: Int
  >   init(_ v: Int) { x = v }
  >   deinit { print(x) } }
  > func f() { let k: K? = K(7)
  >   if let u = k { print(u.x) } }
  > f()
  > SWIFT
  $ ./lab.exe --typecheck g3.swift; echo "exit=$?"
  4:12: error: optional class references are not supported in this subset
  exit=1

`deinit` takes no parameters and there is at most one per class, so a second is a redeclaration:

  $ cat > d2.swift <<'SWIFT'
  > class K { var x: Int
  >   init() { x = 1 }
  >   deinit { print(1) }
  >   deinit { print(2) } }
  > SWIFT
  $ ./lab.exe --typecheck d2.swift; echo "exit=$?"
  4:3: error: invalid redeclaration of 'deinit'
  exit=1

The class rules inherited from concepts 25-27 are unchanged, and the corpus depends on them:
the override diagnostics, `let` properties, and the refusal to `print` or `==` an aggregate.

  $ cat > c25.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1 }
  >   func f() -> Int { return 1 } }
  > class B: A { func f() -> Int { return 2 } }
  > class C { let k: Int
  >   init() { k = 1 } }
  > let c = C()
  > c.k = 5
  > print(c)
  > print(c == c)
  > SWIFT
  $ ./lab.exe --typecheck c25.swift; echo "exit=$?"
  4:14: error: overriding declaration requires an 'override' keyword
  8:1: error: cannot assign to property: 'k' is a 'let' constant
  9:7: error: cannot print a value of type 'C' (only Int, Double, Bool and String)
  10:7: error: binary operator '==' cannot be applied to two 'C' operands
  exit=1
