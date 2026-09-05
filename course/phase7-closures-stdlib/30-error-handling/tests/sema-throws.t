The rules the front end enforces before any of this is lowered (given code, so this file is
green from the start). Swift's error handling is *checked*: a call that can throw is marked at
the call site, and the mark only counts inside something that can handle it.

A throwing call with no `try` — swiftc's exact words:

  $ cat > a.swift <<'SWIFT'
  > enum E: Error { case x }
  > func f() throws -> Int { throw E.x }
  > func g() -> Int { return f() }
  > SWIFT
  $ ./lab.exe --typecheck a.swift
  3:26: error: call can throw, but it is not marked with 'try' and the error is not handled
  [1]

`try` alone is not enough: the call has to sit somewhere the error can go — a `do`, a `try?`,
a `try!`, or a `throws` function that passes it on. This is a different diagnostic because it
is a different mistake.

  $ cat > b.swift <<'SWIFT'
  > enum E: Error { case x }
  > func f() throws -> Int { throw E.x }
  > func g() -> Int { return try f() }
  > SWIFT
  $ ./lab.exe --typecheck b.swift
  3:30: error: errors thrown from here are not handled
  [1]

A METHOD that throws needs `try` just as a function does. Until this was checked,
`acct.withdraw()` type-checked without a `try` — and then swallowed the throw at run time:

  $ cat > m.swift <<'SWIFT'
  > enum E: Error { case x }
  > class A {
  >   var v: Int
  >   init(_ n: Int) { v = n }
  >   func take(_ n: Int) throws -> Int {
  >     if n > v { throw E.x }
  >     return v - n
  >   }
  > }
  > let a = A(10)
  > print(a.take(3))
  > SWIFT
  $ ./lab.exe --typecheck m.swift
  11:7: error: call can throw, but it is not marked with 'try' and the error is not handled
  [1]

`throw` in a function that is not declared `throws`:

  $ cat > c.swift <<'SWIFT'
  > enum E: Error { case x }
  > func g() -> Int { throw E.x }
  > SWIFT
  $ ./lab.exe --typecheck c.swift
  2:19: error: error is not handled because the enclosing function is not declared 'throws'
  [1]

Only an `Error` type can be thrown — an ordinary enum is not one, and neither is an Int:

  $ cat > d.swift <<'SWIFT'
  > enum C { case a }
  > func g() throws -> Int { throw C.a }
  > SWIFT
  $ ./lab.exe --typecheck d.swift
  2:26: error: thrown expression type 'C' does not conform to 'Error'
  [1]

  $ printf 'func g() throws -> Int { throw 5 }\n' > e.swift
  $ ./lab.exe --typecheck e.swift
  1:26: error: thrown expression type 'Int' does not conform to 'Error'
  [1]

The throw path RETURNS a placeholder of the return type — the caller checks the error register
first and discards it — so the return type must be one v0 can invent a value for. A scalar, a
struct, an enum, an optional or nothing all work; a reference does not, because a fake one
would enter the ARC accounting. swiftc has no such limit.

  $ cat > k.swift <<'SWIFT'
  > enum E: Error { case x }
  > class C { var v: Int
  >   init(_ n: Int) { v = n } }
  > func mk(_ n: Int) throws -> C {
  >   if n < 0 { throw E.x }
  >   return C(n)
  > }
  > SWIFT
  $ ./lab.exe --typecheck k.swift
  4:1: error: a throwing function cannot return 'C' in this subset
  [1]

A struct return is fine, and it is not free: the placeholder has to be struct-shaped, or IRGen
emits `ret %P 0` and clang refuses the module.

  $ cat > p.swift <<'SWIFT'
  > enum E: Error { case x }
  > struct P { var x: Int; var y: Int }
  > func mk(_ n: Int) throws -> P {
  >   if n < 0 { throw E.x }
  >   return P(x: n, y: n * 2)
  > }
  > do {
  >   let p = try mk(4)
  >   print(p.x + p.y)
  >   let q = try mk(0 - 1)
  >   print(q.x)
  > } catch { print(0 - 8) }
  > SWIFT
  $ ./lab.exe --typecheck p.swift
