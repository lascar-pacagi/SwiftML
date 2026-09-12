TODO(11c) payload case syntax — postfix parsing keeps `.case(arguments)` as one
`Method_call` node and then continues any remaining postfix chain.

A payload case keeps both positional arguments in source order.

  $ printf 'let command = Command.move(3, true)\n' > payload.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast payload.swift
  (let command (.call Command move 3 true))

The result of a payload case can be the receiver of another postfix member access.

  $ printf 'Shape.circle(5).rawValue\n' > chain.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast chain.swift
  (. (.call Shape circle 5) rawValue)

The closing parenthesis is required before postfix parsing continues.

  $ printf 'Shape.circle(5\n' > bad-close.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-close.swift 2>&1 | head -1
  1:15: error: expected ')'
