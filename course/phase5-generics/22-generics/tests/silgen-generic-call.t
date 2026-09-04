The generic CALL SITE — `TODO(22-silgen)`, the `gfuncs` arm of `Ast.Call`. The generic function
itself is lowered once, with every `T` erased to its constraint's existential (given code), so
the boundary work all happens here: WRAP each argument in a `T` position into `any P`, and OPEN
the result back to the concrete type when the declared return is `T` and the inferred binding is
concrete. The shapes first, in `--emit-sil`; then the programs run, at `-Onone` and `-O`.

ONE copy of the function, whatever the argument types: this is erasure, not specialization
(concept 24 is where the clones appear). Its signature is the erased one, `$any P`:

  $ cat > one.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > struct B: P { func v() -> Int { return 7 } }
  > func first<T: P>(_ a: T, _ b: T) -> T {
  >   if a.v() > b.v() { return a }
  >   return b
  > }
  > print(first(A(x: 3), A(x: 8)).v())
  > print(first(B(), B()).v())
  > EOF
  $ ./lab.exe --emit-sil one.swift | grep '^sil @first'
  sil @first(%0 : $any P, %1 : $any P) -> $any P {
  $ ./lab.exe --emit-sil one.swift | grep -c '^sil @first' || true
  1

The `T` argument is wrapped on the way in and the `T` result is opened on the way out — one
wrap and one open for this one-argument call, and the open names the type inference deduced,
which is what lets `w.x` (a field of `A`, not of `any P`) typecheck and run:

  $ cat > open.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > func id<T: P>(_ t: T) -> T { return t }
  > let w = id(A(x: 8))
  > print(w.v())
  > print(w.x)
  > EOF
  $ ./lab.exe --emit-sil open.swift | grep 'init_existential\|open_existential'
    %2 = init_existential %1 : $A, $any P
    %5 = open_existential %4 : $A
  $ ./lab.exe build open.swift -o open && ./open
  8
  8
  $ ./lab.exe build open.swift -O -o openO && ./openO
  8
  8

A generic returning something that is NOT `T` needs no open at all — nothing came back erased:

  $ cat > noopen.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 6 } }
  > func twice<T: P>(_ t: T) -> Int { return t.v() * 2 }
  > print(twice(A()))
  > EOF
  $ ./lab.exe --emit-sil noopen.swift | grep -c 'open_existential' || true
  0
  $ ./lab.exe build noopen.swift -o noopen && ./noopen
  12

A generic calling a generic stays erased: the inner call's argument is ALREADY an existential,
so there is nothing to wrap, and its `T` result is not concrete, so there is nothing to open —
one wrap for the whole program, at the outer call, and no open:

  $ cat > gg.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 5 } }
  > func inner<T: P>(_ t: T) -> Int { return t.v() }
  > func outer<T: P>(_ t: T) -> Int { return inner(t) + 1 }
  > print(outer(A()))
  > EOF
  $ ./lab.exe --emit-sil gg.swift | grep -c 'init_existential' || true
  1
  $ ./lab.exe --emit-sil gg.swift | grep -c 'open_existential' || true
  0
  $ ./lab.exe build gg.swift -o gg && ./gg
  6

A `where` clause reaches the same lowering — the constraint moved, not changed:

  $ cat > wh.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > struct B: P { func v() -> Int { return 2 } }
  > func one<T: P>(_ t: T) -> Int { return t.v() }
  > func both<T>(_ a: T, _ b: T) -> Int where T: P { return one(a) + one(b) }
  > print(both(A(), A()) + both(B(), B()))
  > EOF
  $ ./lab.exe build wh.swift -o wh && ./wh
  6
  $ ./lab.exe build wh.swift -O -o whO && ./whO
  6

Two different types through the SAME erased function, and a `T` result used concretely on both
sides — the point of the wrap/open pair:

  $ cat > two.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > struct B: P {
  >   var y: Int
  >   func v() -> Int { return y * 10 }
  > }
  > func id<T: P>(_ t: T) -> T { return t }
  > print(id(A(x: 4)).x)
  > print(id(B(y: 4)).y)
  > print(id(A(x: 4)).v() + id(B(y: 4)).v())
  > EOF
  $ ./lab.exe build two.swift -o two && ./two
  4
  4
  44
  $ ./lab.exe build two.swift -O -o twoO && ./twoO
  4
  4
  44

A generic call in a loop, with a non-`T` parameter beside the `T` one:

  $ cat > loop.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > func scale<T: P>(_ t: T, _ k: Int) -> Int { return t.v() * k }
  > var total = 0
  > for i in 0 ..< 5 {
  >   total = total + scale(A(x: i), 3)
  > }
  > print(total)
  > EOF
  $ ./lab.exe build loop.swift -o loop && ./loop
  30
  $ ./lab.exe build loop.swift -O -o loopO && ./loopO
  30
