The edge of the subset the optimizer works inside — GIVEN code, so this file is green from the
start. It is here because every pass you write from now on is judged by `oracle.t`, and a
corpus is only a fair oracle if the front end refuses what the back end cannot lower. These are
the four refusals that keep an aggregate out of IRGen, plus the accepted programs beside them.
`--typecheck` stops after sema: exit 0 and silence is "accepted".

`print` lowers a scalar only, so printing a whole struct is refused here — swiftc accepts it and
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

The same for an enum case and for an optional, the two other aggregates in the subset:

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
