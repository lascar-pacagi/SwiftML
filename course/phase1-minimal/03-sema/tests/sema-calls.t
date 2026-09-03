Calls, through `--typecheck`. The only function is `print(_:)`; it takes exactly one argument.

`bar(z)` is an unknown name AND its argument is still checked: two errors.
In source order, each at its own column:

  $ printf 'bar(z)\n' > call.swift
  $ ./lab.exe --typecheck call.swift
  1:1: error: cannot find 'bar' in scope
  1:5: error: cannot find 'z' in scope
  [1]

`print(1, 2)` is "print(_:) expects exactly one argument", at the call.
Our wording: Swift's print is variadic, ours is not:

  $ printf 'print(1, 2)\n' > arity2.swift
  $ ./lab.exe --typecheck arity2.swift
  1:1: error: print(_:) expects exactly one argument
  [1]

`print()` with no argument is the same arity error:

  $ printf 'print()\n' > arity0.swift
  $ ./lab.exe --typecheck arity0.swift
  1:1: error: print(_:) expects exactly one argument
  [1]

A well-formed call with an arbitrary expression inside is silent:

  $ printf 'let a = 2\nprint(-(a * (a + 1)) %% 7)\n' > ok2.swift
  $ ./lab.exe --typecheck ok2.swift; echo "exit=$?"
  exit=0
