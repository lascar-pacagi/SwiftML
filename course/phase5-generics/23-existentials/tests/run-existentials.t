The whole container story END TO END: boxed and inline conformers through functions, variables,
generics and casts, at `-Onone` and `-O`, printing what swiftc prints. It needs all three holes
— `TODO(23b)`/`TODO(23c)` to build any existential at all, `TODO(23a)` for the casts — so it is
the last file to go green, and it is where a wrong box pointer or a mis-sized buffer shows up as
a wrong number rather than as a shape.

A five-word conformer, boxed, used through a function, a `var` reassignment and a cast, beside
a zero-field one that fits inline:

  $ cat > big.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct Big: P {
  >   var a: Int
  >   var b: Int
  >   var c: Int
  >   var d: Int
  >   var e: Int
  >   func v() -> Int { return a + b + c + d + e }
  > }
  > struct Tiny: P { func v() -> Int { return 100 } }
  > func total(_ x: P, _ y: P) -> Int { return x.v() + y.v() }
  > var p: P = Big(a: 1, b: 2, c: 3, d: 4, e: 5)
  > print(total(p, Tiny()))
  > if let bb = p as? Big { print(bb.e) }
  > p = Tiny()
  > print(p.v())
  > EOF
  $ ./lab.exe build big.swift -o big && ./big
  115
  5
  100
  $ ./lab.exe build big.swift -O -o bigO && ./bigO
  115
  5
  100

`as?` discriminates by the VALUE's dynamic type, not by the static one: the same `any P` answers
`A` and refuses `B`, and the unrelated `C` is the always-nil case sema warned about:

  $ cat > cast.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > struct B: P { func v() -> Int { return -5 } }
  > struct C { var z: Int }
  > let p: P = A(x: 7)
  > if let a = p as? A { print(a.x) } else { print(-1) }
  > if let b = p as? B { print(b.v()) } else { print(-2) }
  > if let c = p as? C { print(c.z) } else { print(-3) }
  > EOF
  $ ./lab.exe build cast.swift -o cast && ./cast
  7
  -2
  -3
  $ ./lab.exe build cast.swift -O -o castO && ./castO
  7
  -2
  -3

A cast inside a loop over a reassigned `var`, so the answer changes from iteration to iteration
— this is the case a devirtualizer must not "prove" away (concept 24 does prove the ones it
can, and this is not one of them):

  $ cat > loop.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > struct B: P { func v() -> Int { return 2 } }
  > var total = 0
  > var p: P = A()
  > for i in 0 ..< 6 {
  >   if let _ = p as? A { total = total + 10 } else { total = total + 1 }
  >   if i % 2 == 0 { p = B() } else { p = A() }
  > }
  > print(total)
  > EOF
  $ ./lab.exe build loop.swift -o loop && ./loop
  33
  $ ./lab.exe build loop.swift -O -o loopO && ./loopO
  33

A successful `as!` yields the concrete value; a failing one ABORTS, the way swiftc's forced cast
does — SIGABRT, exit 134, distinct from the trap's 133. (swiftc's message names the module and
prints addresses, so it is unmatchable; only the code is compared. The `sh -c` wrapper keeps the
shell's nondeterministic "Abort trap: <pid>" job line out of the transcript.)

  $ cat > bang.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > struct B: P { func v() -> Int { return 2 } }
  > let x: P = A()
  > let ok = x as! A
  > print(ok.v())
  > let y = x as! B
  > print(y.v())
  > EOF
  $ ./lab.exe build bang.swift -o bang
  $ sh -c './bang; echo "exit=$?"' 2>/dev/null
  1
  exit=134
  $ swiftc -Onone bang.swift -o swbang 2>/dev/null
  $ sh -c './swbang >/dev/null 2>&1; echo "swiftc exit=$?"' 2>/dev/null
  swiftc exit=134

A boxed conformer through a generic, a cast, and back — the open in `id` and the open in the
cast read the same box:

  $ cat > gen.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct Big: P {
  >   var a: Int
  >   var b: Int
  >   var c: Int
  >   var d: Int
  >   var e: Int
  >   func v() -> Int { return a + b + c + d + e }
  > }
  > func id<T: P>(_ t: T) -> T { return t }
  > let g = id(Big(a: 1, b: 2, c: 3, d: 4, e: 5))
  > print(g.v())
  > print(g.c)
  > let p: P = g
  > if let h = p as? Big { print(h.a + h.e) } else { print(-1) }
  > EOF
  $ ./lab.exe build gen.swift -o gen && ./gen
  15
  3
  6
  $ ./lab.exe build gen.swift -O -o genO && ./genO
  15
  3
  6
