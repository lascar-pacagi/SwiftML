TODO(11c) payload case syntax — postfix parsing keeps `.case(arguments)` as one
`Method_call` node, respects expression precedence, and continues any remaining
postfix chain.

A payload case keeps both positional arguments in source order.

  $ printf 'let command = Command.move(3, true)\n' > payload.swift
  $ python3 timeout.py 0.5 ./lab.exe --emit-ast payload.swift
  (let command (.call Command move 3 true))

An empty argument list is preserved as a postfix call; Sema later decides whether
that member can be called without arguments.

  $ printf 'Factory.make()\n' > empty.swift
  $ python3 timeout.py 0.5 ./lab.exe --emit-ast empty.swift
  (.call Factory make )

A payload construction finishes before the surrounding equality is parsed.

  $ printf 'Shape.circle(1) == Shape.circle(2)\n' > precedence.swift
  $ python3 timeout.py 0.5 ./lab.exe --emit-ast precedence.swift
  (== (.call Shape circle 1) (.call Shape circle 2))

The result of a payload case can be the receiver of another postfix member access.

  $ printf 'Shape.circle(5).rawValue\n' > chain.swift
  $ python3 timeout.py 0.5 ./lab.exe --emit-ast chain.swift
  (. (.call Shape circle 5) rawValue)

Postfix parsing can continue with another call as well as a member read.

  $ printf 'Factory.make().finish(1)\n' > call-chain.swift
  $ python3 timeout.py 0.5 ./lab.exe --emit-ast call-chain.swift
  (.call (.call Factory make ) finish 1)

The closing parenthesis is required before postfix parsing continues.

  $ printf 'Shape.circle(5\n' > bad-close.swift
  $ python3 timeout.py 0.5 ./lab.exe --emit-ast bad-close.swift 2>&1 | head -3
  1:15: error: expected ')'
  Shape.circle(5
                ^
