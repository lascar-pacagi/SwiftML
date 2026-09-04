`fold_binop`, the first `TODO(17)` hole: concept 15's folder knew Int arithmetic on two literals
and nothing else. Now it runs AFTER mem2reg, so a `let` is already a value and folding
propagates through it, and it must cover the six comparisons and `&&`/`||` as well. The driver
around it — recording literals, rewriting the instruction, recording the result — is given; what
you supply is the evaluation. `--sil-opt` prints the whole optimized pipeline.

A comparison of two literals folds to a Bool, which concept 15 left alone:

  $ printf 'print(3 < 5)\n' > b.swift
  $ ./lab.exe --sil-opt b.swift | grep -oE 'integer_literal \$Bool, true'
  integer_literal $Bool, true
  $ ./lab.exe --sil-opt b.swift | grep -c 'binop' || true
  0

All six comparisons fold, and `==`/`!=` fold on Bools too:

  $ printf 'print(3 <= 3)\nprint(4 > 9)\nprint(4 >= 9)\nprint(7 == 7)\nprint(7 != 7)\n' > cmp.swift
  $ ./lab.exe --sil-opt cmp.swift | grep -oE 'integer_literal \$Bool, (true|false)'
  integer_literal $Bool, true
  integer_literal $Bool, false
  integer_literal $Bool, false
  integer_literal $Bool, true
  integer_literal $Bool, false
  $ ./lab.exe --sil-opt cmp.swift | grep -c 'binop' || true
  0

THE PAYOFF over concept 15: folding now reaches through a `let`, because mem2reg turned the slot
into a value. `x * x - (2 + 3)` with `x = 6` becomes the single literal 31:

  $ printf 'let x = 6\nprint(x * x - (2 + 3))\n' > c.swift
  $ ./lab.exe --sil-opt c.swift | grep -oE 'integer_literal \$Int, 31'
  integer_literal $Int, 31
  $ ./lab.exe --sil-opt c.swift | grep -c 'binop' || true
  0
  $ ./lab.exe build c.swift -O -o cO && ./cO
  31

`/` and `%` truncate toward zero, exactly as Swift does, so the folded answer must be the same
one the hardware would have produced:

  $ cat > tr.swift <<'PROG'
  > print(-7 / 2)
  > print(-7 % 3)
  > print(7 % -3)
  > PROG
  $ ./lab.exe --sil-opt tr.swift | grep -oE 'integer_literal \$Int, -?[0-9]+'
  integer_literal $Int, -3
  integer_literal $Int, -1
  integer_literal $Int, 1
  $ ./lab.exe build tr.swift -O -o trO && ./trO
  -3
  -1
  1

`10 / 0` and `10 % 0` are NOT folded — there is no value to fold them to — while the `10 / 2`
beside them is, so the difference is visible rather than the whole file being untouched:

  $ cat > z.swift <<'PROG'
  > print(10 / 2)
  > print(10 / 0)
  > print(10 % 0)
  > PROG
  $ ./lab.exe --sil-opt z.swift | grep -c 'binop' || true
  2
  $ ./lab.exe --sil-opt z.swift | grep -oE 'integer_literal \$Int, 5'
  integer_literal $Int, 5

A value that is not a constant stops the fold: `n` comes from a parameter, so `n * 2` stays a
binop while the `3 + 4` beside it folds:

  $ cat > p.swift <<'PROG'
  > func f(_ n: Int) -> Int {
  >   return n * 2 + (3 + 4)
  > }
  > print(f(5))
  > PROG
  $ ./lab.exe --sil-opt p.swift | grep -c 'binop' || true
  2
  $ ./lab.exe --sil-opt p.swift | grep -oE 'integer_literal \$Int, 7'
  integer_literal $Int, 7
  $ ./lab.exe build p.swift -O -o pO && ./pO
  17

And a loop still computes its own answer at run time — folding a loop-carried value would be
wrong, and the header argument is not a constant. The `2 + 3` inside the body IS folded, so this
case is not passing merely because nothing changed:

  $ cat > s.swift <<'PROG'
  > var s = 0
  > for i in 0 ..< 10 {
  >   if i > 4 { s = s + i * (2 + 3) }
  > }
  > print(s)
  > PROG
  $ ./lab.exe --sil-opt s.swift | grep -oE 'integer_literal \$Int, 5'
  integer_literal $Int, 5
  $ ./lab.exe build s.swift -o s && ./s
  175
  $ ./lab.exe build s.swift -O -o sO && ./sO
  175
