`simplify_cfg`, the second `TODO(17)` hole, in two halves: (a) a `cond_br` whose condition is a
known Bool becomes the taken `br` — keeping THAT side's block arguments — and (b) blocks no
longer reachable from `bb0` are deleted. Half (b) is where block arguments pay off again:
deleting a block deletes its branches, and the stale incoming values go with them, with no
phi-list surgery to do by hand.

A literal `true` condition needs only this hole — no folding — so this case goes green first:
the `cond_br` is gone and so is the `else` block's `print(2)`:

  $ cat > t.swift <<'PROG'
  > if true {
  >   print(1)
  > } else {
  >   print(2)
  > }
  > PROG
  $ ./lab.exe --emit-sil t.swift | grep -c 'cond_br' || true
  1
  $ ./lab.exe --sil-opt t.swift | grep -c 'cond_br' || true
  0
  $ ./lab.exe --sil-opt t.swift | grep -oE 'integer_literal \$Int, [0-9]+'
  integer_literal $Int, 1
  $ ./lab.exe build t.swift -O -o tO && ./tO
  1

Block count is the other half of the claim: the raw SIL has four blocks (entry, then, else,
merge), the optimized one has three — the `else` is not merely branch-free, it is gone:

  $ ./lab.exe --emit-sil t.swift | grep -c '^bb' || true
  4
  $ ./lab.exe --sil-opt t.swift | grep -c '^bb' || true
  3

With `fold_binop` also filled, a computed condition folds first and then this pass straightens
it — `10 > 3` gets the same treatment as the literal:

  $ cat > g.swift <<'PROG'
  > if 10 > 3 {
  >   print(1)
  > } else {
  >   print(2)
  > }
  > PROG
  $ ./lab.exe --sil-opt g.swift | grep -c 'cond_br' || true
  0
  $ ./lab.exe --sil-opt g.swift | grep -oE 'integer_literal \$Int, [0-9]+'
  integer_literal $Int, 1
  $ ./lab.exe build g.swift -O -o gO && ./gO
  1

The FALSE side is taken just as readily — here the `then` block is the one that disappears:

  $ cat > f.swift <<'PROG'
  > if 1 == 2 {
  >   print(3)
  > } else {
  >   print(4)
  > }
  > PROG
  $ ./lab.exe --sil-opt f.swift | grep -oE 'integer_literal \$Int, [0-9]+'
  integer_literal $Int, 4
  $ ./lab.exe build f.swift -O -o fO && ./fO
  4

The taken side's ARGUMENTS have to come with it. Here the branch feeds a merge that takes a
value, so folding the `cond_br` must keep the true edge's `%v` and not the false edge's:

  $ cat > a.swift <<'PROG'
  > var x = 0
  > if true {
  >   x = 11
  > } else {
  >   x = 22
  > }
  > print(x)
  > PROG
  $ ./lab.exe --sil-opt a.swift | grep -oE 'br bb[0-9]+\(%[0-9]+\)'
  br bb2(%4)
  $ ./lab.exe build a.swift -O -o aO && ./aO
  11

`&&` and `||` are not binops in our SIL at all — SILGen lowers them to a branch diamond so the
right operand is skipped when the left decides the answer. So `true && false` is simplified, not
folded: this pass takes the true edge, and the merge's argument is the literal `false` the right
arm produced. (`fold_binop`'s `And`/`Or` arms are still required — a later pass can build such a
binop — and the unit suite calls them directly.)

  $ cat > bo.swift <<'PROG'
  > print(true && false)
  > print(false || true)
  > PROG
  $ ./lab.exe --emit-sil bo.swift | grep -c 'cond_br' || true
  2
  $ ./lab.exe --sil-opt bo.swift | grep -c 'cond_br' || true
  0
  $ ./lab.exe build bo.swift -O -o boO && ./boO
  false
  true

A condition that is NOT constant must survive untouched — a loop test is the case that matters,
and deleting it would turn a loop into straight-line code. The `if true` in the body beside it IS
deleted, so of the three branches in the raw SIL the two real ones survive:

  $ cat > w.swift <<'PROG'
  > var s = 0
  > var i = 0
  > while i < 4 {
  >   if true { s = s + i }
  >   if i > 1 { s = s + 1 }
  >   i = i + 1
  > }
  > print(s)
  > PROG
  $ ./lab.exe --emit-sil w.swift | grep -c 'cond_br' || true
  3
  $ ./lab.exe --sil-opt w.swift | grep -c 'cond_br' || true
  2
  $ ./lab.exe build w.swift -o w && ./w
  8
  $ ./lab.exe build w.swift -O -o wO && ./wO
  8

Iteration is what makes the pair worth running twice: folding a branch exposes the next
constant, which the second `constant-fold`/`simplify-cfg` round then folds. Nested constant
`if`s collapse to one `print`:

  $ cat > n.swift <<'PROG'
  > if 2 > 1 {
  >   if 3 > 4 {
  >     print(7)
  >   } else {
  >     print(8)
  >   }
  > } else {
  >   print(9)
  > }
  > PROG
  $ ./lab.exe --sil-opt n.swift | grep -c 'cond_br' || true
  0
  $ ./lab.exe --sil-opt n.swift | grep -oE 'integer_literal \$Int, [0-9]+'
  integer_literal $Int, 8
  $ ./lab.exe build n.swift -O -o nO && ./nO
  8
