The fourth rule, and the one that makes SSA construction interesting: a loop HEADER is a join
whose second predecessor comes from BELOW it, so the argument it takes is filled with a value
the walk has not computed yet when it first reaches the header. Threading the reaching value
down the dominator tree is what makes that work. Needs `TODO(16)`.

A counting loop: the header takes two arguments — the induction variable and the accumulator —
the entry edge passes their initial values and the latch passes the updated ones, and the loop
body no longer touches memory:

  $ cat > l.swift <<'PROG'
  > var s = 0
  > for i in 0 ..< 3 {
  >   s = s + i
  > }
  > print(s)
  > PROG
  $ ./lab.exe --emit-sil l.swift | grep -cE 'alloc_stack|load|store'
  11
  $ ./lab.exe --sil-opt l.swift | grep -cE 'alloc_stack|load|store' || true
  0
  $ ./lab.exe --sil-opt l.swift | grep -oE 'bb[0-9]+\(%[0-9]+ : \$Int, %[0-9]+ : \$Int\)'
  bb1(%19 : $Int, %20 : $Int)
  $ ./lab.exe --sil-opt l.swift | grep -cE 'br bb[0-9]+\(%[0-9]+, %[0-9]+\)' || true
  2

PRUNED SSA, the rule this concept was rebuilt around: a `let` declared INSIDE the loop body is
dead on the entry edge, so no argument is placed for it — a header that asked for three values
would have nothing to pass on the way in. The header still takes exactly two:

  $ cat > pruned.swift <<'PROG'
  > var t = 0
  > var i = 0
  > while i < 3 {
  >   let d = i * i
  >   t = t + d
  >   i = i + 1
  > }
  > print(t)
  > PROG
  $ ./lab.exe --sil-opt pruned.swift | grep -oE 'bb[0-9]+\([^)]*\)'
  bb1(%3, %0)
  bb1(%24 : $Int, %25 : $Int)
  bb1(%20, %16)
  $ ./lab.exe --sil-opt pruned.swift | grep -cE 'alloc_stack|load|store' || true
  0
  $ ./lab.exe build pruned.swift -O -o prunedO && ./prunedO
  5

`break` and `continue` are extra edges out of and back into the loop, and each one carries the
values its block reached — the answers do not move at `-O`:

  $ cat > bc.swift <<'PROG'
  > var t = 0
  > for i in 0 ..< 8 {
  >   if i == 2 { continue }
  >   if i > 5 { break }
  >   t = t + i
  > }
  > print(t)
  > PROG
  $ ./lab.exe --sil-opt bc.swift | grep -cE 'alloc_stack|load|store' || true
  0
  $ ./lab.exe build bc.swift -o bc && ./bc
  13
  $ ./lab.exe build bc.swift -O -o bcO && ./bcO
  13

A nested loop is a header inside a header: the inner one's arguments are threaded from the outer
one's, and the SIL verifier accepts the result:

  $ cat > nl.swift <<'PROG'
  > var t = 0
  > for i in 0 ..< 4 {
  >   for j in 0 ..< 4 {
  >     if j == i { continue }
  >     t = t + i * j
  >   }
  > }
  > print(t)
  > PROG
  $ ./lab.exe --sil-opt nl.swift | grep -cE 'alloc_stack|load|store' || true
  0
  $ ./lab.exe build nl.swift -O -o nlO && ./nlO
  22

Recursion is not a loop in the CFG — each call has its own frame — but the parameter slot is
promoted just the same, and `fib` must still answer 6765:

  $ cat > fib.swift <<'PROG'
  > func fib(_ n: Int) -> Int {
  >   if n < 2 { return n }
  >   return fib(n - 1) + fib(n - 2)
  > }
  > print(fib(20))
  > PROG
  $ ./lab.exe --sil-opt fib.swift | grep -cE 'alloc_stack|load|store' || true
  0
  $ ./lab.exe build fib.swift -O -o fibO && ./fibO
  6765
