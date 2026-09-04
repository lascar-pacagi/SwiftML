GVN — global value numbering — keeps one copy of a computation the program spells twice. Both
`TODO(18)` holes are needed for anything here to change: `value_key` decides WHEN two
instructions compute the same value, and the scoped walk decides WHERE that answer may be used.
This file is the elimination itself; `opt-gvn-safety.t` is everything it must refuse.

The textbook case, in one block: `x * x + x * x` multiplies twice in raw SIL, once after GVN:

  $ cat > g.swift <<'PROG'
  > func f(_ x: Int) -> Int {
  >   return x * x + x * x
  > }
  > print(f(6))
  > PROG
  $ ./lab.exe --emit-sil g.swift | grep -c 'binop "\*"'
  2
  $ ./lab.exe --sil-opt g.swift | grep -c 'binop "\*"' || true
  1
  $ ./lab.exe build g.swift -O -o gO && ./gO
  72

The addition of two equal values is itself a repeated computation, so the SECOND use is the
canonical value, not a second name for it — one multiply and one add is all that is left:

  $ ./lab.exe --sil-opt g.swift | grep -c 'binop' || true
  2

GLOBAL, not just local: `n * 2` is computed in the condition and in both arms. The condition's
block DOMINATES both arms, so all three uses collapse onto the one in the condition — this is
the "G" in GVN, and it is what the dominator-tree walk buys over a per-block table:

  $ cat > h.swift <<'PROG'
  > func h(_ n: Int) -> Int {
  >   if n * 2 > 10 {
  >     return n * 2
  >   } else {
  >     return n * 2 + 1
  >   }
  > }
  > print(h(7))
  > print(h(2))
  > PROG
  $ ./lab.exe --emit-sil h.swift | grep -c 'binop "\*"'
  3
  $ ./lab.exe --sil-opt h.swift | grep -c 'binop "\*"' || true
  1
  $ ./lab.exe build h.swift -O -o hO && ./hO
  14
  5

Inside a loop the win repeats every iteration: `i * i + i * i` computes one multiply per turn
instead of two, and the answer does not move:

  $ cat > lp.swift <<'PROG'
  > var s = 0
  > for i in 0 ..< 20 {
  >   s = s + i * i + i * i
  > }
  > print(s)
  > PROG
  $ ./lab.exe --emit-sil lp.swift | grep -c 'binop "\*"'
  2
  $ ./lab.exe --sil-opt lp.swift | grep -c 'binop "\*"' || true
  1
  $ ./lab.exe build lp.swift -o lp && ./lp
  4940
  $ ./lab.exe build lp.swift -O -o lpO && ./lpO
  4940

Reads out of a struct VALUE are pure too — after mem2reg `p.x` is a `struct_extract`, and two of
them on the same value are one:

  $ cat > st.swift <<'PROG'
  > struct P {
  >   var x: Int
  > }
  > func f(_ p: P) -> Int {
  >   return p.x + p.x
  > }
  > print(f(P(x: 3)))
  > PROG
  $ ./lab.exe --emit-sil st.swift | grep -c 'struct_extract'
  2
  $ ./lab.exe --sil-opt st.swift | grep -c 'struct_extract' || true
  1
  $ ./lab.exe build st.swift -O -o stO && ./stO
  6

GVN and the folder feed each other, and a program with both a constant and a symbolic repeat
shows the division of labour: `(2 + 3) * (2 + 3)` is folded to 25 and swept away by the folder
and DCE, while the two `(n + 1) * (n + 1)`s need GVN — three multiplies raw, one after:

  $ cat > cf.swift <<'PROG'
  > func f(_ n: Int) -> Int {
  >   return (n + 1) * (n + 1) + (n + 1) * (n + 1) + (2 + 3) * (2 + 3)
  > }
  > print(f(4))
  > PROG
  $ ./lab.exe --emit-sil cf.swift | grep -c 'binop "\*"'
  3
  $ ./lab.exe --sil-opt cf.swift | grep -c 'binop "\*"' || true
  1
  $ ./lab.exe --sil-opt cf.swift | grep -oE 'integer_literal \$Int, 25'
  integer_literal $Int, 25
  $ ./lab.exe build cf.swift -O -o cfO && ./cfO
  75
