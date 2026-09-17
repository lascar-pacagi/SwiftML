What the checker PRODUCES, through `--emit-tast`. Sema does not merely approve a program, it
returns a typed one: every node carries the type the checker concluded, and every name that
resolved is a node that can only mean that. Concept 08's SILGen consumes this tree and re-derives
nothing — see PLAN.md §0.1 for what went wrong when it did.

You can read the same thing out of the oracle: `swiftc -dump-ast` prints its type-checked tree,
with a `type="..."` on every node.

An integer literal beside a Double CARRIES Double — the coercion is recorded, not left to be
rediscovered. This is the line that makes the bug in PLAN.md §0.1 unrepresentable: by the time any
back end sees this tree, the `2` already says what it is:

  $ printf 'let d = 1.5\nprint(d * 2)\n' > t1.swift
  $ ./lab.exe --emit-tast t1.swift
  (let d (double_lit 1.5 : Double))
  (print (* (local d : Double) (int_lit 2 : Double) : Double) : Int)

Compare the oracle on the same program — swiftc keeps the literal's NODE KIND and changes its
type, which is exactly what the line above shows:

  $ printf 'let d = 1.5\nprint(d * 2)\n' > t1b.swift
  $ swiftc -dump-ast t1b.swift 2>&1 | grep -o 'integer_literal_expr type="[A-Za-z]*"' | head -1
  integer_literal_expr type="Double"

An Int-typed *variable* beside a Double does not flex, so no tree is produced at all — the checker
returns no program when it found errors, which is why `--emit-tast` prints nothing here:

  $ printf 'let i = 1\nlet d = 1.5\nprint(d * i)\n' > t2.swift
  $ ./lab.exe --emit-tast t2.swift 2>&1; echo "exit=$?"
  3:7: error: binary operator '*' cannot be applied to operands of type 'Double' and 'Int'
  print(d * i)
        ^
  exit=1

A name that resolved becomes a `local`, and an annotation does not survive: it was a written name,
and the value's recorded type is the resolved answer:

  $ printf 'let x: Double = 1 + 2\nprint(x)\n' > t3.swift
  $ ./lab.exe --emit-tast t3.swift
  (let x (+ (int_lit 1 : Double) (int_lit 2 : Double) : Double))
  (print (local x : Double) : Int)

`1 as Double` keeps its `coerce` node, as swiftc's `coerce_expr` does, with the literal inside it
already carrying Double:

  $ printf 'print(1 as Double)\n' > t4.swift
  $ ./lab.exe --emit-tast t4.swift
  (print (coerce (int_lit 1 : Double) : Double) : Int)
