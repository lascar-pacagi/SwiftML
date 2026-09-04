The `return` statement's rules, through `--typecheck`. Needs the `Ast.Return` arm of
`check_stmt` (with the two-pass driver and `check_func`, which set `current_ret`). Three
messages, all swiftc's; each lands on the `return` keyword.

`return 1` at top level is "return invalid outside of a func"; so is a bare `return`:

  $ printf 'return 1\n' > t1.swift
  $ ./lab.exe --typecheck t1.swift; echo "exit=$?"
  1:1: error: return invalid outside of a func
  exit=1
  $ printf 'let x = 1\nreturn\n' > t2.swift
  $ ./lab.exe --typecheck t2.swift; echo "exit=$?"
  2:1: error: return invalid outside of a func
  exit=1

A `return` in a top-level `if` is still outside any function:

  $ printf 'if true {\n  return 1\n}\n' > t3.swift
  $ ./lab.exe --typecheck t3.swift; echo "exit=$?"
  2:3: error: return invalid outside of a func
  exit=1

`return 1` in a function with no `-> T` is "unexpected non-void return value in void function":

  $ printf 'func f() {\n  return 1\n}\n' > v1.swift
  $ ./lab.exe --typecheck v1.swift; echo "exit=$?"
  2:3: error: unexpected non-void return value in void function
  exit=1

A bare `return` in a `-> Int` function is "non-void function should return a value":

  $ printf 'func f() -> Int {\n  return\n}\n' > v2.swift
  $ ./lab.exe --typecheck v2.swift; echo "exit=$?"
  2:3: error: non-void function should return a value
  exit=1

A bare `return` in a `Void` function is fine — an early exit:

  $ printf 'func f(_ n: Int) {\n  if n == 0 { return }\n  print(n)\n}\n' > v3.swift
  $ ./lab.exe --typecheck v3.swift; echo "exit=$?"
  exit=0

`return "s"` from `-> Int` is a conversion error, checked against the declared type:

  $ printf 'func f() -> Int {\n  return "s"\n}\n' > c1.swift
  $ ./lab.exe --typecheck c1.swift; echo "exit=$?"
  2:10: error: cannot convert value of type 'String' to specified type 'Int'
  exit=1

`return 1` from `-> Bool` is rejected the same way — a literal is not a Bool:

  $ printf 'func f() -> Bool {\n  return 1\n}\n' > c2.swift
  $ ./lab.exe --typecheck c2.swift; echo "exit=$?"
  2:10: error: cannot convert value of type 'Int' to specified type 'Bool'
  exit=1

`return 1` from `-> Double` is accepted — the return type is the contextual type, and the
literal coerces exactly as in `let d: Double = 1`:

  $ printf 'func f() -> Double {\n  return 1\n}\nfunc g() -> Double {\n  return 2 * 3 + 1\n}\n' > c3.swift
  $ ./lab.exe --typecheck c3.swift; echo "exit=$?"
  exit=0

The returned expression is checked in the body's scope — a parameter or local may be returned:

  $ printf 'func f(_ n: Int) -> Int {\n  let m = n * 2\n  return m + n\n}\n' > c4.swift
  $ ./lab.exe --typecheck c4.swift; echo "exit=$?"
  exit=0

A `return` whose value has an error reports that error, not a second one about the return:

  $ printf 'func f() -> Int {\n  return nothere\n}\n' > c5.swift
  $ ./lab.exe --typecheck c5.swift; echo "exit=$?"
  2:10: error: cannot find 'nothere' in scope
  exit=1

Every `return` in a body is checked — two bad ones give two errors:

  $ printf 'func f(_ n: Int) -> Int {\n  if n > 0 { return true }\n  return "no"\n}\n' > c6.swift
  $ ./lab.exe --typecheck c6.swift; echo "exit=$?"
  2:21: error: cannot convert value of type 'Bool' to specified type 'Int'
  3:10: error: cannot convert value of type 'String' to specified type 'Int'
  exit=1
