The conformance check, through `--typecheck`. Needs `struct_conforms` (`TODO(21-sema)`): a
struct conforms to a protocol when EVERY requirement has a method of the same name with the
EXACT signature. The one predicate powers the `struct S: P` diagnostic and the implicit
existential coercion at the four sites (let, argument, return, assignment). Wording is
swiftc's; the position is the struct's name.

A two-requirement protocol with two conformers, used at every coercion site, is silent:

  $ cat > ok.swift <<'EOF'
  > protocol Shape {
  >   func area() -> Int
  >   func scaled(_ k: Int) -> Int
  > }
  > struct Circle: Shape {
  >   var r: Int
  >   func scaled(_ k: Int) -> Int { return 3 * r * r * k }
  >   func area() -> Int { return 3 * r * r }
  > }
  > struct Square: Shape {
  >   var s: Int
  >   func area() -> Int { return s * s }
  >   func scaled(_ k: Int) -> Int { return s * s * k }
  > }
  > func pick(_ big: Bool) -> Shape {
  >   if big { return Square(s: 9) }
  >   return Circle(r: 1)
  > }
  > func show(_ sh: Shape) { print(sh.area()) }
  > let a: Shape = Circle(r: 2)
  > var b: Shape = a
  > b = Square(s: 3)
  > show(pick(true))
  > show(b)
  > print(a.scaled(2))
  > EOF
  $ ./lab.exe --typecheck ok.swift; echo "exit=$?"
  exit=0

A conformer missing a requirement is "type 'C' does not conform to protocol 'S'", at its name:

  $ printf 'protocol S { func area() -> Int }\nstruct C: S { var r: Int }\n' > miss.swift
  $ ./lab.exe --typecheck miss.swift; echo "exit=$?"
  2:8: error: type 'C' does not conform to protocol 'S'
  exit=1

The same words when the method exists with the wrong return type:

  $ cat > ret.swift <<'EOF'
  > protocol S { func area() -> Int }
  > struct C: S {
  >   var r: Int
  >   func area() -> Bool { return true }
  > }
  > EOF
  $ ./lab.exe --typecheck ret.swift; echo "exit=$?"
  2:8: error: type 'C' does not conform to protocol 'S'
  exit=1

And when the parameter types differ — `(Bool) -> Int` does not witness `(Int) -> Int`:

  $ cat > par.swift <<'EOF'
  > protocol S { func grow(_ k: Int) -> Int }
  > struct C: S {
  >   var r: Int
  >   func grow(_ k: Bool) -> Int { return r }
  > }
  > EOF
  $ ./lab.exe --typecheck par.swift; echo "exit=$?"
  2:8: error: type 'C' does not conform to protocol 'S'
  exit=1

Requirement order is irrelevant; only the set matters. Methods declared in the reverse order
of the requirements, plus an extra one, still conform (exit 0):

  $ cat > order.swift <<'EOF'
  > protocol S {
  >   func a() -> Int
  >   func b() -> Bool
  > }
  > struct C: S {
  >   func extra() -> Int { return 0 }
  >   func b() -> Bool { return true }
  >   func a() -> Int { return 1 }
  > }
  > EOF
  $ ./lab.exe --typecheck order.swift; echo "exit=$?"
  exit=0

A struct claiming two protocols is checked against each: failing both is two errors, in
clause order; failing only the second is one:

  $ cat > two.swift <<'EOF'
  > protocol P { func p() -> Int }
  > protocol Q { func q() -> Int }
  > struct Both: P, Q { var x: Int }
  > struct Half: P, Q {
  >   func p() -> Int { return 1 }
  > }
  > EOF
  $ ./lab.exe --typecheck two.swift; echo "exit=$?"
  3:8: error: type 'Both' does not conform to protocol 'P'
  3:8: error: type 'Both' does not conform to protocol 'Q'
  4:8: error: type 'Half' does not conform to protocol 'Q'
  exit=1

The implicit wrap needs the SAME predicate. A non-conformer where `any S` is expected fails
with swiftc's site-specific words — here return, initializer, argument, assignment, in source order:

  $ cat > wrap.swift <<'EOF'
  > protocol S { func area() -> Int }
  > struct C: S {
  >   var r: Int
  >   func area() -> Int { return r }
  > }
  > struct D { var r: Int }
  > func f(_ s: S) -> Int { return s.area() }
  > func g() -> S { return D(r: 1) }
  > let s: S = D(r: 1)
  > print(f(D(r: 2)))
  > var v: S = C(r: 1)
  > v = D(r: 3)
  > EOF
  $ ./lab.exe --typecheck wrap.swift; echo "exit=$?"
  8:24: error: return expression of type 'D' does not conform to 'S'
  9:12: error: value of type 'D' does not conform to specified type 'S'
  10:9: error: argument type 'D' does not conform to expected type 'S'
  12:5: error: cannot assign value of type 'D' to type 'any S'
  exit=1

A non-struct value gets the same site wording (`Int` at an initializer and as an argument):

  $ cat > int.swift <<'EOF'
  > protocol S { func area() -> Int }
  > struct C: S {
  >   var r: Int
  >   func area() -> Int { return r }
  > }
  > func f(_ s: S) -> Int { return s.area() }
  > let s: S = 3
  > print(f(true))
  > EOF
  $ ./lab.exe --typecheck int.swift; echo "exit=$?"
  7:12: error: value of type 'Int' does not conform to specified type 'S'
  8:9: error: argument type 'Bool' does not conform to expected type 'S'
  exit=1

An existential exposes only its requirements: a non-requirement method or a stored property
of the conformer is "value of type 'any S' has no member":

  $ cat > mem.swift <<'EOF'
  > protocol S { func area() -> Int }
  > struct C: S {
  >   var r: Int
  >   func area() -> Int { return r }
  >   func extra() -> Int { return 1 }
  > }
  > let s: S = C(r: 1)
  > print(s.extra())
  > print(s.r)
  > EOF
  $ ./lab.exe --typecheck mem.swift; echo "exit=$?"
  8:7: error: value of type 'any S' has no member 'extra'
  9:7: error: value of type 'any S' has no member 'r'
  exit=1

Two existentials cannot be compared: `==` on `any S` is rejected like swiftc:

  $ cat > eq.swift <<'EOF'
  > protocol S { func area() -> Int }
  > struct C: S {
  >   var r: Int
  >   func area() -> Int { return r }
  > }
  > let a: S = C(r: 1)
  > let b: S = C(r: 1)
  > print(a == b)
  > EOF
  $ ./lab.exe --typecheck eq.swift; echo "exit=$?"
  8:7: error: binary operator '==' cannot be applied to two 'any S' operands
  exit=1

A conformer's method is non-mutating: writing a stored property in it is rejected:

  $ cat > mut.swift <<'EOF'
  > protocol S { func bump() }
  > struct C: S {
  >   var x: Int
  >   func bump() { x = x + 1 }
  > }
  > EOF
  $ ./lab.exe --typecheck mut.swift; echo "exit=$?"
  4:17: error: cannot assign to property: 'self' is immutable
  exit=1

An existential is an aggregate IRGen cannot print, so `print(s)` on an `any S` is refused the
way `print` of a struct is (sema-subset.t) — swiftc accepts it and prints `C(r: 1)`, a
divergence recorded in §2. Calling the requirement and printing THAT is what we support:

  $ cat > pre.swift <<'EOF'
  > protocol S { func area() -> Int }
  > struct C: S {
  >   var r: Int
  >   func area() -> Int { return r }
  > }
  > let s: S = C(r: 1)
  > print(s.area())
  > print(s)
  > EOF
  $ ./lab.exe --typecheck pre.swift; echo "exit=$?"
  8:7: error: cannot print a value of type 'any S' (only Int, Double, Bool and String)
  exit=1
