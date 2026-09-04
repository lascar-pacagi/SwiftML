One function body, through `--typecheck`. Needs `check_func` (and the two-pass driver, which is
what calls it): the parameters bound immutably in a fresh scope, the body checked, and the
"missing return" rule. The cases whose body contains a `return` also need the return arm.

The parameters are in scope in the body — `print(a)` finds `a`:

  $ printf 'func f(_ a: Int, _ b: Bool) {\n  print(a)\n  print(b)\n}\n' > p1.swift
  $ ./lab.exe --typecheck p1.swift; echo "exit=$?"
  exit=0

A parameter is a `let`: `a = 5` in the body is the constant-assignment error:

  $ printf 'func f(_ a: Int) {\n  a = 5\n}\n' > p2.swift
  $ ./lab.exe --typecheck p2.swift; echo "exit=$?"
  2:3: error: cannot assign to value: 'a' is a 'let' constant
  exit=1

A body sees no top-level names — `x` declared outside is not found inside (swiftc would
accept this: our functions are self-contained, a divergence the explainer states):

  $ printf 'let x = 1\nfunc f() {\n  print(x)\n}\n' > p3.swift
  $ ./lab.exe --typecheck p3.swift; echo "exit=$?"
  3:9: error: cannot find 'x' in scope
  exit=1

A parameter does not leak out of its function — `print(a)` after the body cannot find it:

  $ printf 'func f(_ a: Int) { }\nprint(a)\n' > p4.swift
  $ ./lab.exe --typecheck p4.swift; echo "exit=$?"
  2:7: error: cannot find 'a' in scope
  exit=1

A body may declare a local that shadows a parameter:

  $ printf 'func f(_ a: Int) -> Int {\n  let a = 2\n  return a\n}\n' > p5.swift
  $ ./lab.exe --typecheck p5.swift; echo "exit=$?"
  exit=0

An unknown parameter type is "cannot find type 'Nope' in scope"; so is an unknown return
type (both reported on the declaration — a parameter carries no span of its own):

  $ printf 'func f(_ a: Nope) { }\nfunc g() -> Nope { return 1 }\n' > t1.swift
  $ ./lab.exe --typecheck t1.swift; echo "exit=$?"
  1:1: error: cannot find type 'Nope' in scope
  2:1: error: cannot find type 'Nope' in scope
  exit=1

A `Void` function need not return — a body of two prints is fine:

  $ printf 'func f() {\n  print(1)\n  print(2)\n}\n' > v1.swift
  $ ./lab.exe --typecheck v1.swift; echo "exit=$?"
  exit=0

`-> Int` with a body that never returns is the missing-return error, on the declaration:

  $ printf 'func f() -> Int {\n  print(1)\n  print(2)\n}\n' > m1.swift
  $ ./lab.exe --typecheck m1.swift; echo "exit=$?"
  1:1: error: missing return in global function expected to return 'Int'
  exit=1

An `if` with no `else` does not return on every path — `if n > 0 { return 1 }` alone is missing:

  $ printf 'func f(_ n: Int) -> Int {\n  if n > 0 { return 1 }\n}\n' > m2.swift
  $ ./lab.exe --typecheck m2.swift; echo "exit=$?"
  1:1: error: missing return in global function expected to return 'Int'
  exit=1

A `return` inside a loop does not count — the loop may run zero times:

  $ printf 'func f(_ n: Int) -> Int {\n  while n > 0 { return 1 }\n}\n' > m3.swift
  $ ./lab.exe --typecheck m3.swift; echo "exit=$?"
  1:1: error: missing return in global function expected to return 'Int'
  exit=1

An `if` / `else` whose two branches both return is a definite return:

  $ printf 'func f(_ n: Int) -> Int {\n  if n > 0 { return 1 } else { return 2 }\n}\n' > m4.swift
  $ ./lab.exe --typecheck m4.swift; echo "exit=$?"
  exit=0

An `else if` chain returns on every path only if its final `else` does:

  $ printf 'func f(_ n: Int) -> Int {\n  if n > 0 { return 1 } else if n < 0 { return 2 } else { return 0 }\n}\nfunc g(_ n: Int) -> Int {\n  if n > 0 { return 1 } else if n < 0 { return 2 }\n}\n' > m5.swift
  $ ./lab.exe --typecheck m5.swift; echo "exit=$?"
  4:1: error: missing return in global function expected to return 'Int'
  exit=1

A `return` followed by a `print` still returns — what follows a return is unreachable:

  $ printf 'func f() -> Int {\n  print(1)\n  return 1\n}\nfunc g() -> Int {\n  return 1\n  print(2)\n}\n' > m6.swift
  $ ./lab.exe --typecheck m6.swift; echo "exit=$?"
  exit=0

Each function is checked on its own — errors in two bodies are both reported, in order:

  $ printf 'func f() -> Int {\n  print(1)\n}\nfunc g(_ a: Int) {\n  a = 1\n}\n' > two.swift
  $ ./lab.exe --typecheck two.swift; echo "exit=$?"
  1:1: error: missing return in global function expected to return 'Int'
  5:3: error: cannot assign to value: 'a' is a 'let' constant
  exit=1
