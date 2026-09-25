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
  print(p)
        ^
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
  print(e)
        ^
  7:7: error: cannot print a value of type 'Int?' (only Int, Double, Bool and String)
  print(o)
        ^
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
  print(a == b)
        ^
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
  print(a == b)
        ^
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
  c.k = 5
  ^
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
  c.n = 5
  ^
  [1]

The conformance CLAUSE is checked for shape before any requirement is looked at, so this last
pair is given too: a struct in the clause is "inheritance from non-protocol type", an unknown
name is "cannot find type" — both at the conforming type's name, where swiftc reports them:

  $ printf 'struct D { var r: Int }\nstruct C: D { var r: Int }\nstruct E: Nope { var r: Int }\n' > notp.swift
  $ ./lab.exe --typecheck notp.swift; echo "exit=$?"
  2:8: error: inheritance from non-protocol type 'D'
  struct C: D { var r: Int }
         ^
  3:8: error: cannot find type 'Nope' in scope
  struct E: Nope { var r: Int }
         ^
  exit=1


`any Nope` is reported once; calling a method on it adds nothing, since a value of unknown type
has every member:

  $ cat > unknown-any.swift <<'EOF'
  > let a: any Nope = 1
  > let b: Int = a.f()
  > EOF
  $ ./lab.exe --typecheck unknown-any.swift; echo "exit=$?"
  1:1: error: cannot find type 'Nope' in scope
  let a: any Nope = 1
  ^
  exit=1

An undeclared name is reported once per use and is TError afterwards, never a guessed Int: the
call `nope(1)` and the variable `nope` go into a Bool annotation, a condition and a `+` with a
Bool, and nothing else is reported — the same rule as an unknown type, one level down:

  $ printf 'let b: Bool = nope(1)\nlet c: Bool = nope\nif nope {\n  print(nope + true)\n}\n' > unknown-names.swift
  $ ./lab.exe --typecheck unknown-names.swift; echo "exit=$?"
  1:15: error: cannot find 'nope' in scope
  let b: Bool = nope(1)
                ^
  2:15: error: cannot find 'nope' in scope
  let c: Bool = nope
                ^
  3:4: error: cannot find 'nope' in scope
  if nope {
     ^
  4:9: error: cannot find 'nope' in scope
    print(nope + true)
          ^
  exit=1
