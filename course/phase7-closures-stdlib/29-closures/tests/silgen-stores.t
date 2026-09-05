The store lowerings the closure work sits on (given code). A captured struct, an optional field
and a Double operand all reach a `store`, and each one wants its value generated AT the type of
the place it is going — these three cases pin that.

Writing a field of an optional type wraps: `s.o = 5` must store `.some(5)`, tag and all, not a
bare 5 over the tag word.

  $ cat > opt.swift <<'SWIFT'
  > struct S { var o: Int? }
  > var s = S(o: nil)
  > s.o = 5
  > print(s.o ?? 0)
  > SWIFT
  $ ./lab.exe build opt.swift -o opt && ./opt
  5

`self.v = e` inside a class method has no stack slot to find — concept 27 stopped spilling
class-typed parameters, so `self` is a borrow held in SSA. Looking for a slot raised `Not_found`
and killed the compiler.

  $ cat > self.swift <<'SWIFT'
  > class C { var v: Int
  >   init(_ x: Int) { v = x }
  >   func bump() { self.v = v + 1 } }
  > let c = C(1)
  > c.bump()
  > c.bump()
  > print(c.v)
  > SWIFT
  $ ./lab.exe build self.swift -o self && ./self
  3

An Int literal beside a Double adopts the Double — sema's `unify` says so, and the lowering has
to agree, or IRGen emits `fmul double %d, 2` and clang rejects the module:

  $ cat > dbl.swift <<'SWIFT'
  > let d: Double = 2.5
  > let e = d * 2
  > print(e > 4.0)
  > print(2 * d > 4.0)
  > SWIFT
  $ ./lab.exe build dbl.swift -o dbl && ./dbl
  true
  true
