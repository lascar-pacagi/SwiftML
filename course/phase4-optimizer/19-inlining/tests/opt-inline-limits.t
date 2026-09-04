What v0 does NOT inline, and why. `inlinable` is given: a callee qualifies only if it is a
single-block LEAF that is not `main`. Both halves matter — a callee with a call inside could be
recursive and never terminate, and a callee with more than one block would need its CFG stitched
into the caller's, which is exercise 2. Every case here pairs the callee that stays with one
that goes, so a `TODO(19)` that inlines nothing does not pass by refusing everything.

A RECURSIVE function calls itself, so it is not a leaf and is not inlined — while the leaf
beside it is, and the module keeps `main` and `fib` alone:

  $ cat > f.swift <<'PROG'
  > func sq(_ x: Int) -> Int {
  >   return x * x
  > }
  > func fib(_ n: Int) -> Int {
  >   if n < 2 { return n }
  >   return fib(n - 1) + fib(n - 2)
  > }
  > print(fib(20) + sq(3))
  > PROG
  $ ./lab.exe --emit-sil f.swift | grep -oE '^sil @[a-z]+'
  sil @sq
  sil @fib
  sil @main
  $ ./lab.exe --sil-opt f.swift | grep -oE '^sil @[a-z]+'
  sil @fib
  sil @main
  $ ./lab.exe build f.swift -O -o fO && ./fO
  6774

A MULTI-BLOCK leaf is left alone in v0: `clamp` has an `if`, so its body is three blocks and
splicing it would mean splitting the caller's block at the call site:

  $ cat > c.swift <<'PROG'
  > func clamp(_ x: Int) -> Int {
  >   if x < 0 {
  >     return 0
  >   } else {
  >     return x
  >   }
  > }
  > func sq(_ x: Int) -> Int {
  >   return x * x
  > }
  > print(clamp(-3) + clamp(7) + sq(2))
  > PROG
  $ ./lab.exe --emit-sil c.swift | grep -oE '^sil @[a-z]+'
  sil @clamp
  sil @sq
  sil @main
  $ ./lab.exe --sil-opt c.swift | grep -oE '^sil @[a-z]+'
  sil @clamp
  sil @main
  $ ./lab.exe build c.swift -o c && ./c
  11
  $ ./lab.exe build c.swift -O -o cO && ./cO
  11

A single-block leaf that is called TWICE is inlined at both sites — copying is the whole
mechanism, and code size is the price the cost model in exercise 1 would put a limit on:

  $ cat > tw.swift <<'PROG'
  > func sq(_ x: Int) -> Int {
  >   return x * x
  > }
  > func f(_ n: Int) -> Int {
  >   return sq(n) + sq(n + 1)
  > }
  > print(f(3))
  > PROG
  $ ./lab.exe --emit-sil tw.swift | grep -c 'apply %'
  3
  $ ./lab.exe --sil-opt tw.swift | grep -c 'apply %' || true
  0
  $ ./lab.exe --sil-opt tw.swift | grep -oE '^sil @[a-z]+'
  sil @main
  $ ./lab.exe build tw.swift -O -o twO && ./twO
  25

MUTUAL recursion is caught by the same leaf rule from both sides — neither is a leaf, so neither
is inlined, and the leaf beside them goes as usual:

  $ cat > mu.swift <<'PROG'
  > func isEven(_ n: Int) -> Bool {
  >   if n == 0 { return true }
  >   return isOdd(n - 1)
  > }
  > func isOdd(_ n: Int) -> Bool {
  >   if n == 0 { return false }
  >   return isEven(n - 1)
  > }
  > func sq(_ x: Int) -> Int {
  >   return x * x
  > }
  > print(isEven(10))
  > print(isOdd(10))
  > print(sq(3))
  > PROG
  $ ./lab.exe --emit-sil mu.swift | grep -oE '^sil @[a-zA-Z]+'
  sil @isEven
  sil @isOdd
  sil @sq
  sil @main
  $ ./lab.exe --sil-opt mu.swift | grep -oE '^sil @[a-zA-Z]+'
  sil @isEven
  sil @isOdd
  sil @main
  $ ./lab.exe build mu.swift -o mu && ./mu
  true
  false
  9
  $ ./lab.exe build mu.swift -O -o muO && ./muO
  true
  false
  9

`main` is never a callee, and a function that is still called after the pass is never dropped.
Here `sq` is inlined into `sumSq` and disappears with it, while `sumSq` stays because `main` is
still calling it — one `apply` left in the module, and it is that one:

  $ cat > k.swift <<'PROG'
  > func sq(_ x: Int) -> Int {
  >   return x * x
  > }
  > func sumSq(_ n: Int) -> Int {
  >   var s = 0
  >   var i = 0
  >   while i < n {
  >     s = s + sq(i)
  >     i = i + 1
  >   }
  >   return s
  > }
  > print(sumSq(5))
  > PROG
  $ ./lab.exe --sil-opt k.swift | grep -oE '^sil @[a-zA-Z]+'
  sil @sumSq
  sil @main
  $ ./lab.exe --sil-opt k.swift | grep -c 'apply %' || true
  1
  $ ./lab.exe build k.swift -o k && ./k
  30
  $ ./lab.exe build k.swift -O -o kO && ./kO
  30
