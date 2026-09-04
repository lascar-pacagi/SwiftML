Method dispatch — `TODO(21b)`, the `Method_call` arm of `gen_expr`, and the last hole. A
concrete struct receiver is a STATIC call: `function_ref @S.m` applied with the receiver as
argument 0. An existential receiver is DYNAMIC: `witness_method %e, #slot ; apply(args)`, the
slot being the requirement's index in the protocol. The shapes first, in `--emit-sil`; then the
programs run, at `-Onone` and `-O`, and print what swiftc prints.

A call on a concrete value is a direct apply of `@Circle.area` with self first — no table:

  $ cat > static.swift <<'EOF'
  > protocol Shape { func area() -> Int }
  > struct Circle: Shape {
  >   var r: Int
  >   func area() -> Int { return 3 * r * r }
  > }
  > let c = Circle(r: 2)
  > print(c.area())
  > EOF
  $ ./lab.exe --emit-sil static.swift | grep -B1 'apply %[0-9]*(%'
    %5 = function_ref @Circle.area
    %6 = apply %5(%4)
  $ ./lab.exe --emit-sil static.swift | grep -c 'witness_method' || true
  0

A call on an existential goes through the table, by slot: `area` is requirement #0 and
`perimeter` is #1, whatever order the conformer defined them in:

  $ cat > dyn.swift <<'EOF'
  > protocol Shape {
  >   func area() -> Int
  >   func perimeter() -> Int
  > }
  > struct Square: Shape {
  >   var s: Int
  >   func perimeter() -> Int { return 4 * s }
  >   func area() -> Int { return s * s }
  > }
  > let sh: Shape = Square(s: 3)
  > print(sh.perimeter())
  > print(sh.area())
  > EOF
  $ ./lab.exe --emit-sil dyn.swift | grep 'witness_method'
    %6 = witness_method %5, #1 ; apply() $Int
    %9 = witness_method %8, #0 ; apply() $Int
  $ ./lab.exe build dyn.swift -o dyn && ./dyn
  12
  9

A requirement with a parameter: the argument is lowered to the requirement's parameter type
(here a concrete `Circle` is wrapped on the way into `combine(_: Shape)`):

  $ cat > arg.swift <<'EOF'
  > protocol Shape {
  >   func area() -> Int
  >   func combine(_ other: Shape) -> Int
  > }
  > struct Circle: Shape {
  >   var r: Int
  >   func area() -> Int { return 3 * r * r }
  >   func combine(_ other: Shape) -> Int { return area() + other.area() }
  > }
  > let a: Shape = Circle(r: 1)
  > print(a.combine(Circle(r: 2)))
  > EOF
  $ ./lab.exe --emit-sil arg.swift | grep -c 'init_existential'
  2
  $ ./lab.exe build arg.swift -o arg && ./arg
  15

Heterogeneous dispatch — one call site, two concrete types — is the point of the table.
swiftc prints 19, 27, 4; so must we, at -Onone and -O:

  $ cat > hetero.swift <<'EOF'
  > protocol Shape { func area() -> Int }
  > struct Circle: Shape {
  >   var r: Int
  >   func area() -> Int { return 3 * r * r }
  > }
  > struct Square: Shape {
  >   var s: Int
  >   func area() -> Int { return s * s }
  > }
  > func total(_ a: Shape, _ b: Shape) -> Int { return a.area() + b.area() }
  > print(total(Circle(r: 1), Square(s: 4)))
  > var z: Shape = Circle(r: 3)
  > print(z.area())
  > z = Square(s: 2)
  > print(z.area())
  > EOF
  $ ./lab.exe build hetero.swift -o hetero && ./hetero
  19
  27
  4
  $ ./lab.exe build hetero.swift -O -o heteroO && ./heteroO
  19
  27
  4

Reassigning an existential `var` re-wraps (the Assign-wrap miscompile of the status notes:
a raw store of the new struct left the OLD table in place, and dispatch went to the wrong
method). Each reassignment must dispatch to the new type — 1, 100, 1, 10000:

  $ cat > reassign.swift <<'EOF'
  > protocol Shape { func area() -> Int }
  > struct One: Shape { func area() -> Int { return 1 } }
  > struct Hundred: Shape { func area() -> Int { return 100 } }
  > struct Big: Shape {
  >   var a: Int
  >   var b: Int
  >   func area() -> Int { return a * b }
  > }
  > var z: Shape = One()
  > print(z.area())
  > z = Hundred()
  > print(z.area())
  > z = One()
  > print(z.area())
  > z = Big(a: 100, b: 100)
  > print(z.area())
  > EOF
  $ ./lab.exe build reassign.swift -o reassign && ./reassign
  1
  100
  1
  10000
  $ ./lab.exe build reassign.swift -O -o reassignO && ./reassignO
  1
  100
  1
  10000

Zero-field conformers under `-O` (the GVN type-blind-key bug: `struct () $Zero` and
`struct () $One` have the same operands and were merged, so both calls dispatched through one
table). Both types must keep their own identity — 0 then 1:

  $ cat > zero.swift <<'EOF'
  > protocol Num { func v() -> Int }
  > struct Zero: Num { func v() -> Int { return 0 } }
  > struct One: Num { func v() -> Int { return 1 } }
  > func show(_ n: Num) { print(n.v()) }
  > show(Zero())
  > show(One())
  > EOF
  $ ./lab.exe build zero.swift -O -o zeroO && ./zeroO
  0
  1

A Void requirement, and a requirement called from inside another method through `self`
(bare `area()` inside `describe` is a static call on self):

  $ cat > void.swift <<'EOF'
  > protocol Shape {
  >   func area() -> Int
  >   func describe()
  > }
  > struct Square: Shape {
  >   var s: Int
  >   func area() -> Int { return s * s }
  >   func describe() { print(area()) }
  > }
  > struct Dot: Shape {
  >   func area() -> Int { return 0 }
  >   func describe() { print(-1) }
  > }
  > func report(_ sh: Shape) { sh.describe() }
  > report(Square(s: 5))
  > report(Dot())
  > EOF
  $ ./lab.exe build void.swift -o void && ./void
  25
  -1
  $ ./lab.exe build void.swift -O -o voidO && ./voidO
  25
  -1

An optional of an existential: `Shape?` wraps twice — the struct into `any Shape`, that into
`.some` — and `if let` unwraps to a dispatching existential; `nil` prints the fallback:

  $ cat > opt.swift <<'EOF'
  > protocol Shape { func area() -> Int }
  > struct Circle: Shape {
  >   var r: Int
  >   func area() -> Int { return 3 * r * r }
  > }
  > func find(_ k: Int) -> Shape? {
  >   if k > 0 { return Circle(r: k) }
  >   return nil
  > }
  > for k in 0 ..< 3 {
  >   if let sh = find(k) { print(sh.area()) } else { print(-1) }
  > }
  > EOF
  $ ./lab.exe build opt.swift -o opt && ./opt
  -1
  3
  12
  $ ./lab.exe build opt.swift -O -o optO && ./optO
  -1
  3
  12
