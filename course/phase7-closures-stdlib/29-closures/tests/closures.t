Closures: function types, by-value capture, the thin/thick ABI. RED until the TODO(29) holes
(silgen lifting; irgen indirect call).

The lifting is visible in SIL — the closure becomes a top-level function taking a CONTEXT,
the capture is copied in at creation, and the call goes through the pair:

  $ cat > mk.swift <<'SWIFT'
  > func makeAdder(_ n: Int) -> (Int) -> Int {
  >   return { (x: Int) -> Int in x + n }
  > }
  > let a = makeAdder(7)
  > print(a(1))
  > SWIFT
  $ ./lab.exe --emit-sil mk.swift | grep -c 'closure @makeAdder\$clo0'
  1
  $ ./lab.exe --emit-sil mk.swift | grep -c 'capture_get'
  1
  $ ./lab.exe --emit-sil mk.swift | grep -c 'apply_value'
  1
  $ ./lab.exe build mk.swift -o mk && ./mk
  8

Each call mints a FRESH context — two adders don't share state; a named function becomes a
value through a thunk with a null context:

  $ cat > a.swift <<'SWIFT'
  > let double = { (x: Int) -> Int in x * 2 }
  > print(double(21))
  > func apply(_ f: (Int) -> Int, _ x: Int) -> Int { return f(x) }
  > print(apply(double, 10))
  > func makeAdder(_ n: Int) -> (Int) -> Int {
  >   return { (x: Int) -> Int in x + n }
  > }
  > let add7 = makeAdder(7)
  > let add9 = makeAdder(9)
  > print(add7(1) + add9(1))
  > func dbl(_ x: Int) -> Int { return x * 2 }
  > let g = dbl
  > print(g(50))
  > SWIFT
  $ ./lab.exe build a.swift -o a && ./a
  42
  20
  18
  100
  $ ./lab.exe build a.swift -O -o aO && ./aO
  42
  20
  18
  100

Struct captures, reassigned function vars, and the ARC interplay (the Box dies at reader's
scope exit because the closure captured the VALUE, not the object):

  $ cat > b.swift <<'SWIFT'
  > struct P { var x: Int
  >   var y: Int }
  > func scaler(_ p: P) -> (Int) -> Int {
  >   return { (k: Int) -> Int in p.x * k + p.y }
  > }
  > var f = scaler(P(x: 3, y: 1))
  > print(f(10))
  > f = scaler(P(x: 5, y: 2))
  > print(f(10))
  > class Box { var v: Int
  >   init(_ x: Int) { v = x }
  >   deinit { print(v) } }
  > func reader(_ n: Int) -> () -> Int {
  >   let b = Box(n)
  >   let v = b.v
  >   return { () -> Int in v * 2 }
  > }
  > let r = reader(21)
  > print(r())
  > print(9)
  > SWIFT
  $ ./lab.exe build b.swift -o b && ./b
  31
  52
  21
  42
  9

The capture discipline is enforced — managed values (classes, function values) cannot be
captured in v0 (the context would need retain/destroy machinery; an exercise). Mutating a
capture can't even parse: closure bodies are single EXPRESSIONS in v0, so the by-value
question never arises syntactically:

  $ cat > c2.swift <<'SWIFT'
  > class K { var v: Int
  >   init() { v = 1 } }
  > let k = K()
  > let f = { () -> Int in k.v }
  > SWIFT
  $ ./lab.exe --typecheck c2.swift 2>&1 | head -1
  4:24: error: cannot capture 'k' in this subset (closure captures are plain values)
