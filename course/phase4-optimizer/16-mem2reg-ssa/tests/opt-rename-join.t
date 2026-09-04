The third rule of the renaming walk: at a JOIN the reaching value differs per incoming edge, so
the block takes an ARGUMENT and every branch into it hands over the value that reached the end
of ITS block. This is where block arguments earn their keep over LLVM's phi nodes — the value
travels on the edge, in the terminator, instead of in a list inside the target block. Needs
`TODO(16)`; the placement of the argument is given, filling the branches is yours.

A `var` written on both arms of an `if`: the merge block takes one argument and each `br`
carries its arm's literal, so the two stores and the load disappear:

  $ cat > j.swift <<'PROG'
  > var x = 0
  > if 3 < 5 {
  >   x = 100
  > } else {
  >   x = 200
  > }
  > print(x)
  > PROG
  $ ./lab.exe --emit-sil j.swift | grep -cE 'alloc_stack|load|store'
  5
  $ ./lab.exe --sil-opt j.swift | grep -cE 'alloc_stack|load|store' || true
  0
  $ ./lab.exe --sil-opt j.swift | grep -oE 'bb[0-9]+\([^)]*\)'
  bb2(%6)
  bb2(%12 : $Int)
  bb2(%8)
  $ ./lab.exe --sil-opt j.swift | grep -oE 'br bb[0-9]+\(%[0-9]+\)'
  br bb2(%6)
  br bb2(%8)

Only ONE argument is placed, for the one variable live across the merge — the condition's
operands are already values and never lived in a slot:

  $ ./lab.exe --sil-opt j.swift | grep -c ': $Int' || true
  1

An arm that does NOT write still has to hand over a value. With no `else` there is no block to
put a `br` in, so the missing arm is the `cond_br`'s own false edge — and it carries the 7 from
before the `if`:

  $ cat > one.swift <<'PROG'
  > var x = 7
  > if 3 < 5 {
  >   x = 100
  > }
  > print(x)
  > PROG
  $ ./lab.exe --sil-opt one.swift | grep -oE 'cond_br %[0-9]+, bb[0-9]+, bb[0-9]+\(%[0-9]+\)'
  cond_br %5, bb1, bb2(%0)
  $ ./lab.exe --sil-opt one.swift | grep -oE 'integer_literal \$Int, 7'
  integer_literal $Int, 7
  $ ./lab.exe build one.swift -O -o oneO && ./oneO
  100

Nested joins thread through each other: the inner merge takes one argument for `x` and hands it
on to the outer merge, which takes two — and the answers do not move at `-O`:

  $ cat > nest.swift <<'PROG'
  > var x = 0
  > var y = 0
  > if 1 < 2 {
  >   if 3 < 4 { x = 5 } else { x = 6 }
  >   y = x + 1
  > } else {
  >   x = 9
  >   y = 0
  > }
  > print(x)
  > print(y)
  > PROG
  $ ./lab.exe --sil-opt nest.swift | grep -cE 'alloc_stack|load|store' || true
  0
  $ ./lab.exe --sil-opt nest.swift | grep -oE 'bb[0-9]+\([^)]* : [^)]*\)'
  bb2(%28 : $Int, %29 : $Int)
  bb5(%30 : $Int)
  $ ./lab.exe build nest.swift -o nest && ./nest
  5
  6
  $ ./lab.exe build nest.swift -O -o nestO && ./nestO
  5
  6

A variable that is dead after the join gets NO argument — placement is pruned by liveness, and
renaming must not invent one:

  $ cat > dead.swift <<'PROG'
  > var x = 0
  > if 1 < 2 { x = 5 } else { x = 6 }
  > print(1)
  > PROG
  $ ./lab.exe --sil-opt dead.swift | grep -c 'bb[0-9]*(' || true
  0
