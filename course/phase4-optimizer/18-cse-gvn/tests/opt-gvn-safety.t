What GVN must REFUSE to merge. Both `TODO(18)` holes decide this together: `value_key` returns
None for anything impure or unique, and the walk POPS the keys a block added before visiting its
sibling — the pop is the whole correctness argument, because a value may be reused only where
its definition dominates the use. Every case here pairs the thing that must not merge with one
that must, so a `value_key` that keys nothing does not pass by refusing everything.

A CALL is not a value: two `f(n)`s may print, trap or recurse, so both stay (three `apply`s in
the module, counting the `t(5)` that calls them) — while the `n * n` beside them, being pure, is
merged:

  $ cat > ap.swift <<'PROG'
  > func f(_ x: Int) -> Int {
  >   return x + 1
  > }
  > func t(_ n: Int) -> Int {
  >   return f(n) + f(n) + n * n + n * n
  > }
  > print(t(5))
  > PROG
  $ ./lab.exe --emit-sil ap.swift | grep -c 'apply %'
  3
  $ ./lab.exe --sil-opt ap.swift | grep -c 'apply %' || true
  3
  $ ./lab.exe --emit-sil ap.swift | grep -c 'binop "\*"'
  2
  $ ./lab.exe --sil-opt ap.swift | grep -c 'binop "\*"' || true
  1
  $ ./lab.exe build ap.swift -O -o apO && ./apO
  62

SIBLING scopes must not see each other. `n * 3` is computed in the `then` arm and again in the
`else` arm; neither dominates the other, so one survives in each — while the repeat WITHIN the
`then` arm is merged. A table that never popped would share across the arms, and the `else` arm
would read a value that was never computed on its path:

  $ cat > sib.swift <<'PROG'
  > func g(_ n: Int) -> Int {
  >   var r = 0
  >   if n > 0 {
  >     r = n * 3 + n * 3
  >   } else {
  >     r = n * 3 + 1
  >   }
  >   return r
  > }
  > print(g(4))
  > print(g(-4))
  > PROG
  $ ./lab.exe --emit-sil sib.swift | grep -c 'binop "\*"'
  3
  $ ./lab.exe --sil-opt sib.swift | grep -c 'binop "\*"' || true
  2
  $ ./lab.exe build sib.swift -o sib && ./sib
  24
  -11
  $ ./lab.exe build sib.swift -O -o sibO && ./sibO
  24
  -11

TYPE IS PART OF THE VALUE — a bug this course actually shipped. `A(x: 1)` and `B(x: 1)` build
from the same operand but are different values; merging them produced ill-typed LLVM and the
`-O` build failed. `value_key` folds the result type into the key of a `struct` and an `enum`, so
the two `A(x: 1)`s become one and the `B(x: 1)` stays apart — three `struct`s raw, two after:

  $ cat > tt.swift <<'PROG'
  > struct A {
  >   var x: Int
  > }
  > struct B {
  >   var x: Int
  > }
  > func fb(_ b: B) -> Int {
  >   return b.x
  > }
  > let a = A(x: 1)
  > let a2 = A(x: 1)
  > print(a.x + a2.x + fb(B(x: 1)))
  > PROG
  $ ./lab.exe --emit-sil tt.swift | grep -c 'struct ('
  3
  $ ./lab.exe --sil-opt tt.swift | grep -c 'struct (' || true
  2
  $ ./lab.exe build tt.swift -o tt && ./tt
  3
  $ ./lab.exe build tt.swift -O -o ttO && ./ttO
  3

The same for two enums with the same tag and no payload — different types, different values:

  $ cat > te.swift <<'PROG'
  > enum E {
  >   case a
  >   case b
  > }
  > enum F {
  >   case a
  >   case b
  > }
  > let e = E.a
  > let e2 = E.a
  > let f = F.a
  > print(e == e2)
  > print(f == F.b)
  > PROG
  $ ./lab.exe --emit-sil te.swift | grep -c 'enum #'
  4
  $ ./lab.exe --sil-opt te.swift | grep -c 'enum #' || true
  3
  $ ./lab.exe build te.swift -o te && ./te
  true
  false
  $ ./lab.exe build te.swift -O -o teO && ./teO
  true
  false

A loop-carried value is a block ARGUMENT, not an expression, so it is never keyed — and the
computations that depend on it are keyed per iteration's canonical value, not shared across the
back edge. The counting loop still counts:

  $ cat > bl.swift <<'PROG'
  > var s = 0
  > var i = 0
  > while i < 5 {
  >   s = s + i * i + i * i
  >   i = i + 1
  > }
  > print(s)
  > PROG
  $ ./lab.exe --emit-sil bl.swift | grep -c 'binop "\*"'
  2
  $ ./lab.exe --sil-opt bl.swift | grep -c 'binop "\*"' || true
  1
  $ ./lab.exe build bl.swift -o bl && ./bl
  60
  $ ./lab.exe build bl.swift -O -o blO && ./blO
  60
