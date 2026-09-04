The `TODO(19)` transform: replace an `apply` with a copy of the callee's body. This is the first
INTER-procedural pass — it rewrites one function using another — and everything in it is
bookkeeping: renumber the callee's values past the caller's, bind each parameter to the actual
argument, carry the value types across, and make the call's result BE whatever the callee
returned. This file is the splice and its payoff; `opt-inline-limits.t` is what stays alone.

`sq(5)` is inlined, so `main` gains the multiply and loses the call — and with the body in
place the folder finishes the job, leaving the literal 25 and no call at all:

  $ cat > q.swift <<'PROG'
  > func sq(_ x: Int) -> Int {
  >   return x * x
  > }
  > print(sq(5))
  > PROG
  $ ./lab.exe --emit-sil q.swift | grep -c '^sil @'
  2
  $ ./lab.exe --sil-opt q.swift | grep -c '^sil @' || true
  1
  $ ./lab.exe --emit-sil q.swift | grep -c 'apply %'
  1
  $ ./lab.exe --sil-opt q.swift | grep -c 'apply %' || true
  0
  $ ./lab.exe --sil-opt q.swift | grep -oE 'integer_literal \$Int, 25'
  integer_literal $Int, 25

`@sq` is gone from the module: once nothing calls it, the pass drops it. Note the check counts
`apply`s and not `function_ref`s — a leftover reference to an inlined-away callee would keep it
alive forever:

  $ ./lab.exe --sil-opt q.swift | grep -oE '^sil @[a-z]+'
  sil @main
  $ ./lab.exe build q.swift -O -o qO && ./qO
  25

THE CASCADE is the point. Two calls in a loop body become two spliced bodies, GVN then merges
what they share and the folder simplifies what is left — one `apply` per call becomes none:

  $ cat > lp.swift <<'PROG'
  > func sq(_ x: Int) -> Int {
  >   return x * x
  > }
  > func dbl(_ x: Int) -> Int {
  >   return x + x
  > }
  > var s = 0
  > for i in 0 ..< 5 {
  >   s = s + sq(i) + dbl(i)
  > }
  > print(s)
  > PROG
  $ ./lab.exe --emit-sil lp.swift | grep -c '^sil @'
  3
  $ ./lab.exe --sil-opt lp.swift | grep -c '^sil @' || true
  1
  $ ./lab.exe --emit-sil lp.swift | grep -c 'apply %'
  2
  $ ./lab.exe --sil-opt lp.swift | grep -c 'apply %' || true
  0
  $ ./lab.exe build lp.swift -o lp && ./lp
  50
  $ ./lab.exe build lp.swift -O -o lpO && ./lpO
  50

Each parameter binds to ITS argument, in order — a two-parameter callee whose arguments are not
symmetric is where an off-by-one in the mapping shows up as a wrong answer rather than a crash:

  $ cat > sub.swift <<'PROG'
  > func minus(_ a: Int, _ b: Int) -> Int {
  >   return a - b
  > }
  > print(minus(10, 3))
  > print(minus(3, 10))
  > PROG
  $ ./lab.exe --sil-opt sub.swift | grep -oE 'integer_literal \$Int, -?[0-9]+'
  integer_literal $Int, 7
  integer_literal $Int, -7
  $ ./lab.exe build sub.swift -O -o subO && ./subO
  7
  -7

Inlining feeds inlining: a call whose ARGUMENT is itself a call gives the worklist a second
round, and nothing is left of either callee:

  $ cat > n.swift <<'PROG'
  > func add(_ a: Int, _ b: Int) -> Int {
  >   return a + b
  > }
  > func mul(_ a: Int, _ b: Int) -> Int {
  >   return a * b
  > }
  > print(add(mul(3, 4), mul(5, 6)))
  > PROG
  $ ./lab.exe --sil-opt n.swift | grep -c '^sil @' || true
  1
  $ ./lab.exe --sil-opt n.swift | grep -oE 'integer_literal \$Int, 42'
  integer_literal $Int, 42
  $ ./lab.exe build n.swift -O -o nO && ./nO
  42

A callee that returns a struct splices just as well — the value types have to travel with the
instructions, or the caller's `val_ty` has no entry for the spliced values:

  $ cat > st.swift <<'PROG'
  > struct P {
  >   var x: Int
  >   var y: Int
  > }
  > func mk(_ n: Int) -> P {
  >   return P(x: n, y: n * 2)
  > }
  > let p = mk(4)
  > print(p.x + p.y)
  > PROG
  $ ./lab.exe --sil-opt st.swift | grep -c 'apply %' || true
  0
  $ ./lab.exe build st.swift -o st && ./st
  12
  $ ./lab.exe build st.swift -O -o stO && ./stO
  12
