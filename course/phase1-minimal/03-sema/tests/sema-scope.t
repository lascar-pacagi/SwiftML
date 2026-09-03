Name resolution, through `--typecheck` (lex → parse → sema, no codegen — like `swiftc -typecheck`).
Every case here needs `sema.ml : check`. Wording is compared against swiftc's.

A valid program is silent and exits 0. It reassigns a `var` and reads earlier bindings, none of
which may be falsely rejected:

  $ printf 'let a = 2\nvar c = a + 1\nc = c * a\nprint(c)\n' > ok.swift
  $ ./lab.exe --typecheck ok.swift; echo "exit=$?"
  exit=0

`print(y)` with no `y` declared: "cannot find 'y' in scope" at the name, exit 1:

  $ printf 'print(y)\n' > u1.swift
  $ ./lab.exe --typecheck u1.swift; echo "exit=$?"
  1:7: error: cannot find 'y' in scope
  exit=1

Assigning to an undeclared name is the same "in scope" error:

  $ printf 'x = 5\n' > u2.swift
  $ ./lab.exe --typecheck u2.swift
  1:1: error: cannot find 'x' in scope
  [1]

`let a = a` reads an unbound `a`: a name is in scope only AFTER its declaration.
The initializer must be checked before the name is bound — bind first and this is silently
accepted:

  $ printf 'let a = a\n' > u3.swift
  $ ./lab.exe --typecheck u3.swift
  1:9: error: cannot find 'a' in scope
  [1]

An unknown name is found however deep it sits: `-(a * (a + y))`.
Under unary minus, inside nested parentheses, on the right of a binary operator — anything
less means the walk stopped early:

  $ printf 'let a = 1\nprint(-(a * (a + y)) %% 2)\n' > deep.swift
  $ ./lab.exe --typecheck deep.swift
  2:18: error: cannot find 'y' in scope
  [1]

Several problems in one file are ALL reported, in source order, at their columns.
One run tells you everything it can see:

  $ printf 'print(p + q)\nlet a = 1\nfoo(a)\n' > multi.swift
  $ ./lab.exe --typecheck multi.swift
  1:7: error: cannot find 'p' in scope
  1:11: error: cannot find 'q' in scope
  3:1: error: cannot find 'foo' in scope
  [1]
