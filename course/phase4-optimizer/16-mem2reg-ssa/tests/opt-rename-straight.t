The renaming walk with no join in sight — the first two of its four rules. Needs the `TODO(16)`
hole in `mem2reg`'s `rename`: a store to a promotable slot redefines that slot's reaching value,
a load becomes it, and the slot itself goes with them. Nothing here needs a block argument, so
this file goes green before the branch rules do. `--sil-opt` runs the whole pipeline, so concept
15's folder now sees THROUGH the promoted slots — that is the payoff, and the counts show it.
Every memory count is printed raw first, then optimized.

Two `let`s and their sum: the raw SIL touches memory six times, the optimized SIL not at all —
and `x + y` folds to the literal 3, which concept 15 could not do:

  $ printf 'let x = 1\nlet y = 2\nprint(x + y)\n' > lets.swift
  $ ./lab.exe --emit-sil lets.swift | grep -cE 'alloc_stack|load|store'
  6
  $ ./lab.exe --sil-opt lets.swift | grep -cE 'alloc_stack|load|store' || true
  0
  $ ./lab.exe --sil-opt lets.swift | grep -o 'integer_literal $Int, 3'
  integer_literal $Int, 3

Straight-line code has one reaching value per slot and no join, so no block takes an argument:

  $ ./lab.exe --sil-opt lets.swift | grep -c 'bb[0-9]*(' || true
  0

A `var` reassigned twice: each store redefines `x` and each load takes the latest definition, so
`(1 + 1) * 10` folds to 20 and nothing is left in memory:

  $ printf 'var x = 1\nx = x + 1\nx = x * 10\nprint(x)\n' > re.swift
  $ ./lab.exe --emit-sil re.swift | grep -c 'store'
  3
  $ ./lab.exe --sil-opt re.swift | grep -cE 'alloc_stack|load|store' || true
  0
  $ ./lab.exe --sil-opt re.swift | grep -o 'integer_literal $Int, 20'
  integer_literal $Int, 20

A parameter is spilled to a slot on entry in raw SIL; after renaming the body reads `%0`, the
parameter value itself:

  $ printf 'func add1(_ n: Int) -> Int {\n  let m = n + 1\n  return m\n}\nprint(add1(4))\n' > param.swift
  $ ./lab.exe --emit-sil param.swift | grep -c 'alloc_stack'
  2
  $ ./lab.exe --sil-opt param.swift | grep -c 'alloc_stack' || true
  0
  $ ./lab.exe --sil-opt param.swift | grep -o 'binop "+" %0'
  binop "+" %0

A slot holding a whole struct is promotable too — it is only ever loaded and stored, never
addressed field by field, so `p.x + p.y` reads out of the `struct` VALUE:

  $ printf 'struct P {\n  var x: Int\n  var y: Int\n}\nlet p = P(x: 1, y: 2)\nprint(p.x + p.y)\n' > whole.swift
  $ ./lab.exe --sil-opt whole.swift | grep -cE 'alloc_stack|load|store' || true
  0
  $ ./lab.exe --sil-opt whole.swift | grep -c 'struct_extract' || true
  2

A slot that IS addressed field by field is not promotable, and renaming must leave it alone —
`p.x = 9` needs `struct_element_addr`, which takes the slot's address:

  $ printf 'struct P {\n  var x: Int\n  var y: Int\n}\nvar p = P(x: 1, y: 2)\np.x = 9\nprint(p.x)\n' > field.swift
  $ ./lab.exe --sil-opt field.swift | grep -c 'alloc_stack' || true
  1
  $ ./lab.exe build field.swift -O -o fieldO && ./fieldO
  9

`-O` preserves behaviour: the three promoted programs still print 3, 20 and 5:

  $ ./lab.exe build lets.swift -O -o letsO && ./letsO
  3
  $ ./lab.exe build re.swift -O -o reO && ./reO
  20
  $ ./lab.exe build param.swift -O -o paramO && ./paramO
  5
