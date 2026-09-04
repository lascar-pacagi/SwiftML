Constant folding, through `--sil-opt`. Needs the `TODO(15)` hole in `constant_fold` (and the
pass manager to run it): a `binop` of two known Int literals becomes the literal it computes,
and the result is a known literal too, so chains collapse. The given `dead_instr_elim` then
sweeps the literals and binops nothing uses any more. Each count is raw, then optimized.

`1 + 2 * 3` is two binops in raw SIL and none after folding — it is the literal 7:

  $ printf 'print(1 + 2 * 3)\n' > c.swift
  $ ./lab.exe --emit-sil c.swift | grep -c 'binop'; ./lab.exe --sil-opt c.swift | grep -c 'binop' || true
  2
  0
  $ ./lab.exe --sil-opt c.swift | grep -o 'integer_literal $Int, 7'
  integer_literal $Int, 7

A chain folds all the way: `1 + 2 + 3 + 4` becomes the literal 10, with no binop left:

  $ printf 'print(1 + 2 + 3 + 4)\n' > chain.swift
  $ ./lab.exe --sil-opt chain.swift | grep -c 'binop' || true
  0
  $ ./lab.exe --sil-opt chain.swift | grep -o 'integer_literal $Int, 10'
  integer_literal $Int, 10

Folding uses Swift's truncating division and remainder: `(0 - 7) / 2` is -3, `(0 - 7) % 3` is -1:

  $ printf 'print((0 - 7) / 2)\nprint((0 - 7) %% 3)\n' > neg.swift
  $ ./lab.exe --sil-opt neg.swift | grep -o 'integer_literal $Int, -[0-9]*'
  integer_literal $Int, -3
  integer_literal $Int, -1

`10 / 0` and `10 % 0` are NOT folded — `eval_binop` refuses them — while `10 / 2` is:

  $ printf 'print(10 / 0)\nprint(10 %% 0)\nprint(10 / 2)\n' > zero.swift
  $ ./lab.exe --sil-opt zero.swift | grep -o 'binop "[/%]"\|integer_literal $Int, 5'
  binop "/"
  binop "%"
  integer_literal $Int, 5

A comparison is left alone in this concept: `3 < 5` stays a binop while `3 + 5` folds (17 folds it):

  $ printf 'print(3 < 5)\nprint(3 + 5)\n' > cmp.swift
  $ ./lab.exe --sil-opt cmp.swift | grep -o 'binop "."'
  binop "<"

The limit of this pass: `x + y` with `x`, `y` in slots is a binop of two LOADS, so it stays
while the literal `1 + 2` beside it folds. (Concept 16 promotes the slots; then this pass folds it.)

  $ printf 'let x = 1\nlet y = 2\nprint(x + y)\nprint(1 + 2)\n' > mem.swift
  $ ./lab.exe --emit-sil mem.swift | grep -c 'binop'; ./lab.exe --sil-opt mem.swift | grep -c 'binop'
  2
  1

`-O` preserves behaviour: the program, folded to no binop at all, still prints 7 and 10:

  $ printf 'print(1 + 2 * 3)\nprint(1 + 2 + 3 + 4)\n' > run.swift
  $ ./lab.exe --sil-opt run.swift | grep -c 'binop' || true; ./lab.exe build run.swift -O -o runO && ./runO
  0
  7
  10

A loop with side effects survives `-O`: of its 5 binops only `(1 + 1)` folds — the other four
read `i` or `s` from a slot — and the optimized binary still prints 20:

  $ printf 'var s = 0\nfor i in 0 ..< 5 {\n  s = s + i * (1 + 1)\n}\nprint(s)\n' > loop.swift
  $ ./lab.exe --emit-sil loop.swift | grep -c 'binop'; ./lab.exe --sil-opt loop.swift | grep -c 'binop'; ./lab.exe build loop.swift -O -o loopO && ./loopO
  5
  4
  20
