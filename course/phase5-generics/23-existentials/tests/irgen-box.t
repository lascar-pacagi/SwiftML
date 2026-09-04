The existential CONTAINER — `TODO(23b)` (the write) and `TODO(23c)` (the read), in `irgen.ml`,
seen through `--emit-llvm`. Every protocol gets the SAME container, `{ [3 x i64], ptr }`: three
words of payload and a table pointer. A conformer that fits goes in directly; one that does not
is heap-boxed, and the buffer's FIRST WORD holds the box pointer. The fixed size is not a
simplification — it is what separate compilation requires, since a caller must lay out `any P`
without knowing every conformer in the program.

A conformer of three words or fewer is written straight into the buffer: the struct is stored
whole, into the site's `[3 x i64]` (the second of the two stores below — the first is the
ordinary `let` slot), and there is no `malloc` anywhere in the module:

  $ cat > small.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct Two: P {
  >   var a: Int
  >   var b: Int
  >   func v() -> Int { return a + b }
  > }
  > let p: P = Two(a: 3, b: 4)
  > print(p.v())
  > EOF
  $ ./lab.exe --emit-llvm small.swift | grep -c 'call ptr @malloc' || true
  0
  $ ./lab.exe --emit-llvm small.swift | grep 'store %Two'
    store %Two %v0, ptr %v1
    store %Two %v2, ptr %ex3

A five-word conformer does not fit, so the payload is boxed: one `malloc` of its 40 bytes, the
value stored into the box, and the box POINTER stored into the buffer:

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
  > let p: P = Big(a: 1, b: 2, c: 3, d: 4, e: 5)
  > print(p.v())
  > EOF
  $ ./lab.exe --emit-llvm big.swift | grep -c 'call ptr @malloc' || true
  1
  $ ./lab.exe --emit-llvm big.swift | grep -c 'store ptr' || true
  1

Both conformers in one program: the container type is the same `{ [3 x i64], ptr }` for both,
whatever their sizes — that is the whole point — and exactly one of the two wraps boxes:

  $ cat > mix.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct Tiny: P { func v() -> Int { return 1 } }
  > struct Big: P {
  >   var a: Int
  >   var b: Int
  >   var c: Int
  >   var d: Int
  >   var e: Int
  >   func v() -> Int { return a + b + c + d + e }
  > }
  > func total(_ x: P, _ y: P) -> Int { return x.v() + y.v() }
  > print(total(Tiny(), Big(a: 1, b: 2, c: 3, d: 4, e: 5)))
  > EOF
  $ ./lab.exe --emit-llvm mix.swift | grep '%any.P = type'
  %any.P = type { [3 x i64], ptr }
  $ ./lab.exe --emit-llvm mix.swift | grep -c 'call ptr @malloc' || true
  1

The READ is the mirror image (`TODO(23c)`): opening a payload that fits is one load out of the
buffer; opening a boxed one is two — the box pointer out of word 0, then the value out of the
box. A generic's `-> T` result is opened by the same instruction, so this program exercises the
read on a BOXED payload without any cast, and the numbers say whether the second load found the
box: `g.e` is 5 and `g.v()` is 15.

  $ cat > open.swift <<'EOF'
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
  > print(g.e)
  > print(g.v())
  > EOF
  $ ./lab.exe --emit-llvm open.swift | grep -c 'call ptr @malloc' || true
  1
  $ ./lab.exe build open.swift -o open && ./open
  5
  15

And the inline case reads back with a single load — same source, a two-word conformer:

  $ cat > opens.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct Two: P {
  >   var a: Int
  >   var b: Int
  >   func v() -> Int { return a + b }
  > }
  > func id<T: P>(_ t: T) -> T { return t }
  > let g = id(Two(a: 3, b: 4))
  > print(g.b)
  > print(g.v())
  > EOF
  $ ./lab.exe --emit-llvm opens.swift | grep -c 'call ptr @malloc' || true
  0
  $ ./lab.exe build opens.swift -o opens && ./opens
  4
  7
