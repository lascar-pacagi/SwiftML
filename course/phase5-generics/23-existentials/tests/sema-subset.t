The edge of the subset this concept works inside — GIVEN code, so this file is green from the
start. It is here because `oracle.t` is only a fair test while the corpus stays inside what
swiftc and we mean the same thing by, and this is where that boundary is written down: the
refusals that keep an aggregate out of IRGen, plus the accepted programs beside them.
`--typecheck` stops after sema: exit 0 and silence is "accepted".

`print` lowers a scalar only, so printing a whole struct is refused — swiftc accepts it and
prints `P(x: 1)`, an honest divergence (§2); printing the field is fine:

  $ cat > pr.swift <<'PROG'
  > struct P {
  >   var x: Int
  > }
  > let p = P(x: 1)
  > print(p.x)
  > print(p)
  > PROG
  $ ./lab.exe --typecheck pr.swift
  6:7: error: cannot print a value of type 'P' (only Int, Double, Bool and String)
  [1]

The same for an enum case and for an optional, the two other aggregates carried in from
phase 3 (the existential this concept adds is refused the same way — see sema-conformance.t):

  $ cat > pr2.swift <<'PROG'
  > enum E {
  >   case a
  > }
  > let e = E.a
  > let o: Int? = 5
  > print(e)
  > print(o)
  > PROG
  $ ./lab.exe --typecheck pr2.swift
  6:7: error: cannot print a value of type 'E' (only Int, Double, Bool and String)
  7:7: error: cannot print a value of type 'Int?' (only Int, Double, Bool and String)
  [1]

`==` on two structs is refused in swiftc's own words — there is no aggregate compare in SIL,
and `P` has no `Equatable` conformance to synthesize one from:

  $ cat > eq.swift <<'PROG'
  > struct P {
  >   var x: Int
  > }
  > let a = P(x: 1)
  > let b = P(x: 2)
  > print(a == b)
  > PROG
  $ ./lab.exe --typecheck eq.swift
  6:7: error: binary operator '==' cannot be applied to two 'P' operands
  [1]

`==` on two optionals is refused too, and here swiftc accepts (`Int?` is `Equatable`) — the
comparison we do support is against `nil`, which reads the tag:

  $ cat > eqo.swift <<'PROG'
  > let a: Int? = 1
  > let b: Int? = 2
  > print(a == nil)
  > print(a == b)
  > PROG
  $ ./lab.exe --typecheck eqo.swift
  4:7: error: binary operator '==' cannot be applied to two 'Int?' operands
  [1]

A `let` stored property cannot be assigned through any binding, however `var` the binding is —
the `var` property beside it can:

  $ cat > lf.swift <<'PROG'
  > struct C {
  >   let k: Int
  >   var n: Int
  > }
  > var c = C(k: 1, n: 2)
  > c.n = 5
  > c.k = 5
  > PROG
  $ ./lab.exe --typecheck lf.swift
  7:1: error: cannot assign to property: 'k' is a 'let' constant
  [1]

And a `let` binding freezes every property, `var` ones included — swiftc names the binding, not
the field, which is why our message does too:

  $ cat > lb.swift <<'PROG'
  > struct C {
  >   var n: Int
  > }
  > let c = C(n: 2)
  > c.n = 5
  > PROG
  $ ./lab.exe --typecheck lb.swift
  5:1: error: cannot assign to property: 'c' is a 'let' constant
  [1]

The conformance CLAUSE is checked for shape before any requirement is looked at, so this last
pair is given too: a struct in the clause is "inheritance from non-protocol type", an unknown
name is "cannot find type" — both at the conforming type's name, where swiftc reports them:

  $ printf 'struct D { var r: Int }\nstruct C: D { var r: Int }\nstruct E: Nope { var r: Int }\n' > notp.swift
  $ ./lab.exe --typecheck notp.swift; echo "exit=$?"
  2:8: error: inheritance from non-protocol type 'D'
  3:8: error: cannot find type 'Nope' in scope
  exit=1


This concept's own front-end rules are given too. A cast to a type that does not conform to the
operand's protocol can never succeed, so sema WARNS with swiftc's sentence and lets the program
build — `as?` on it is always `nil`. Note this is a warning, not an error: exit 0, and
`--typecheck` prints warnings as well as errors (it did not always, and a promoted golden
caught it):

  $ cat > unrel.swift <<'PROG'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > struct C { var z: Int }
  > let p: P = A(x: 7)
  > if let a = p as? A { print(a.x) }
  > if let c = p as? C { print(c.z) } else { print(-2) }
  > PROG
  $ ./lab.exe --typecheck unrel.swift; echo "exit=$?"
  9:12: warning: cast from 'any P' to unrelated type 'C' always fails
  exit=0

The operand of a cast must be an existential — there is nothing dynamic about a concrete value,
and no table to compare:

  $ cat > conc.swift <<'PROG'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > let a = A(x: 1)
  > if let b = a as? A { print(b.x) }
  > PROG
  $ ./lab.exe --typecheck conc.swift; echo "exit=$?"
  7:12: error: cannot cast a value of type 'A' (only existentials support as?/as! in this subset)
  exit=1

`as?` produces an optional of the target and `as!` produces the target itself, so the two are
not interchangeable — a `let a: A = p as? A` is an optional where a struct is wanted:

  $ cat > types.swift <<'PROG'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > let p: P = A(x: 1)
  > let ok: A = p as! A
  > print(ok.x)
  > let bad: A = p as? A
  > PROG
  $ ./lab.exe --typecheck types.swift; echo "exit=$?"
  9:14: error: cannot convert value of type 'A?' to specified type 'A'
  exit=1
