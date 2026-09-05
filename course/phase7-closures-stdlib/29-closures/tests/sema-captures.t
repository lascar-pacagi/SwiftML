The capture discipline and the type rules around function values (given code, so this file is
green from the start — it states the boundary of the v0 you are filling in).

A closure captures PODs by value. A class reference cannot be captured: the context would need
a retain at creation and a release at destruction, which is per-type copy/destroy machinery the
context's no-op vtable does not have. swiftc accepts this program; we refuse it, and say why.

  $ cat > k.swift <<'SWIFT'
  > class K { var v: Int
  >   init() { v = 1 } }
  > let k = K()
  > let f = { () -> Int in k.v }
  > SWIFT
  $ ./lab.exe --typecheck k.swift
  4:24: error: cannot capture 'k' in this subset (closure captures are plain values)
  [1]

CALLING a captured function value is a capture too — the `{code, ctx}` pair goes into the
context by value and nothing retains the context, so an inner closure outlives its own
environment. It is refused with the same message as naming one; left accepted, `compose` below
printed 8 where swiftc prints 14.

  $ cat > compose.swift <<'SWIFT'
  > func mkAdd(_ n: Int) -> (Int) -> Int {
  >   return { (x: Int) -> Int in x + n }
  > }
  > func compose(_ n: Int) -> (Int) -> Int {
  >   let inner = mkAdd(n)
  >   return { (x: Int) -> Int in inner(x) * 2 }
  > }
  > SWIFT
  $ ./lab.exe --typecheck compose.swift
  6:31: error: cannot capture 'inner' in this subset (closure captures are plain values)
  [1]

A free variable that names nothing is an ordinary scope error, reported once — the closure body
is checked once, against its annotation:

  $ cat > y.swift <<'SWIFT'
  > let f = { (x: Int) -> Int in x + y }
  > SWIFT
  $ ./lab.exe --typecheck y.swift
  1:34: error: cannot find 'y' in scope
  [1]

A `let` stored property is written once, by the initializer that owns it — never through a
binding. This is swiftc's rule and its wording:

  $ cat > letf.swift <<'SWIFT'
  > struct P { let x: Int; var y: Int }
  > var p = P(x: 1, y: 2)
  > p.x = 9
  > SWIFT
  $ ./lab.exe --typecheck letf.swift
  3:1: error: cannot assign to property: 'x' is a 'let' constant
  [1]

Two aggregates cannot be compared: neither a struct nor a function value is Equatable here, and
the back end has no aggregate compare. swiftc refuses `a == b` in the same words; reaching
IRGen, it used to emit `add i64 %struct` and die inside clang.

  $ cat > eq.swift <<'SWIFT'
  > struct P { var x: Int; var y: Int }
  > let a = P(x: 1, y: 2)
  > let b = P(x: 1, y: 2)
  > print(a == b)
  > SWIFT
  $ ./lab.exe --typecheck eq.swift
  4:7: error: binary operator '==' cannot be applied to two 'P' operands
  [1]

`print` takes the four scalar types. swiftc would print `P(x: 1, y: 2)` — printing an aggregate
needs reflection, which we do not have — so this is a divergence we STATE rather than crash on:

  $ cat > pr.swift <<'SWIFT'
  > struct P { var x: Int; var y: Int }
  > print(P(x: 1, y: 2))
  > SWIFT
  $ ./lab.exe --typecheck pr.swift
  2:7: error: cannot print a value of type 'P' (only Int, Double, Bool and String)
  [1]

An optional class reference is refused up front (concept 26's v0 guard): a bitwise-copied
reference inside an enum payload is invisible to the ARC insertion. The annotated `let` path
used to skip this check and produce a function the ownership verifier then rejected.

  $ cat > ok.swift <<'SWIFT'
  > class K { var v: Int
  >   init(_ x: Int) { v = x } }
  > let k: K? = K(1)
  > SWIFT
  $ ./lab.exe --typecheck ok.swift
  3:1: error: optional class references are not supported in this subset
  [1]
