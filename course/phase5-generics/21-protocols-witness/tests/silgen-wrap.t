The existential wrap, through `--emit-sil`. Needs `TODO(21a)` in `gen_expr_as` (and the
tables of `TODO(21c)`, which every module lowers through): where `any P` is expected, a
concrete struct value becomes `init_existential %v : $S, $any P` — the payload paired with
its witness table — and a value that is already `any P` passes through untouched. No method
is called here; dispatch is the next hole.

A `let` with an `any Shape` annotation wraps its concrete initializer:

  $ cat > let.swift <<'EOF'
  > protocol Shape { func area() -> Int }
  > struct Circle: Shape {
  >   var r: Int
  >   func area() -> Int { return 3 * r * r }
  > }
  > let s: Shape = Circle(r: 2)
  > print(1)
  > EOF
  $ ./lab.exe --emit-sil let.swift | grep 'init_existential'
    %2 = init_existential %1 : $Circle, $any Shape

All four coercion sites wrap — initializer, argument, return, assignment — and the wrapped
value is stored in the slot as the existential (the slot's type is `$any Shape`):

  $ cat > sites.swift <<'EOF'
  > protocol Shape { func area() -> Int }
  > struct Circle: Shape {
  >   var r: Int
  >   func area() -> Int { return 3 * r * r }
  > }
  > struct Square: Shape {
  >   var s: Int
  >   func area() -> Int { return s * s }
  > }
  > func keep(_ sh: Shape) { print(0) }
  > func make() -> Shape { return Square(s: 1) }
  > var v: Shape = Circle(r: 2)
  > keep(Circle(r: 3))
  > v = Square(s: 4)
  > EOF
  $ ./lab.exe --emit-sil sites.swift | grep 'init_existential'
    %2 = init_existential %1 : $Square, $any Shape
    %2 = init_existential %1 : $Circle, $any Shape
    %7 = init_existential %6 : $Circle, $any Shape
    %12 = init_existential %11 : $Square, $any Shape
  $ ./lab.exe --emit-sil sites.swift | grep 'alloc_stack.*any Shape'
    %1 = alloc_stack $any Shape  // sh
    %3 = alloc_stack $any Shape  // v

An existential passed where an existential is expected is NOT wrapped again — two wraps for
two concrete values, none for the five existential-to-existential moves:

  $ cat > pass.swift <<'EOF'
  > protocol Shape { func area() -> Int }
  > struct Circle: Shape {
  >   var r: Int
  >   func area() -> Int { return 3 * r * r }
  > }
  > func keep(_ sh: Shape) { print(0) }
  > func same(_ sh: Shape) -> Shape { return sh }
  > let a: Shape = Circle(r: 1)
  > let b: Shape = a
  > var c: Shape = Circle(r: 2)
  > c = b
  > keep(same(c))
  > EOF
  $ ./lab.exe --emit-sil pass.swift | grep -c 'init_existential'
  2

The wrap names the CONFORMANCE, so the same struct wrapped into two protocols names two
different tables:

  $ cat > two.swift <<'EOF'
  > protocol P { func p() -> Int }
  > protocol Q { func q() -> Int }
  > struct Both: P, Q {
  >   func p() -> Int { return 1 }
  >   func q() -> Int { return 2 }
  > }
  > let asP: P = Both()
  > let asQ: Q = Both()
  > print(1)
  > EOF
  $ ./lab.exe --emit-sil two.swift | grep 'init_existential'
    %1 = init_existential %0 : $Both, $any P
    %5 = init_existential %4 : $Both, $any Q

A struct where `Shape?` is expected is wrapped TWICE — into `any Shape`, then into `.some`
(the payload of an optional needs its own coercion; a raw struct in the `.some` slot was a
real miscompile, caught by the oracle). `nil` is just the `.none` tag:

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
  > let o: Shape? = Circle(r: 1)
  > print(1)
  > EOF
  $ ./lab.exe --emit-sil opt.swift | grep 'init_existential\|enum #'
    %8 = init_existential %7 : $Circle, $any Shape
    %9 = enum #1 (%8) $any Shape?
    %10 = enum #0 () $any Shape?
    %2 = init_existential %1 : $Circle, $any Shape
    %3 = enum #1 (%2) $any Shape?
