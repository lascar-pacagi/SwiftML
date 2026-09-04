The two-pass driver, through `--typecheck`. Needs the last `TODO(07)` in `sema.ml` — until it
exists nothing in sema runs, so every sema file reads `TODO`. The cases that call a function
need the other three holes too (`check_func`, `return`, the call); the first four do not.

A program with no functions is still checked: a bad top-level `let` is rejected as in 06:

  $ printf 'let x: Int = "s"\n' > s1.swift
  $ ./lab.exe --typecheck s1.swift; echo "exit=$?"
  1:14: error: cannot convert value of type 'String' to specified type 'Int'
  exit=1

A statement-only program is accepted, exit 0:

  $ printf 'let n = 2\nprint(n * 3)\n' > s2.swift
  $ ./lab.exe --typecheck s2.swift; echo "exit=$?"
  exit=0

Declaring `f` twice is "invalid redeclaration of 'f'", reported on the second one:

  $ printf 'func f() { }\nfunc f() { }\n' > d1.swift
  $ ./lab.exe --typecheck d1.swift; echo "exit=$?"
  2:1: error: invalid redeclaration of 'f'
  exit=1

A statement between two declarations is checked in its place — pass 2 walks items in order:

  $ printf 'func a() { }\nlet q: Int = true\nfunc b() { }\n' > o1.swift
  $ ./lab.exe --typecheck o1.swift; echo "exit=$?"
  2:14: error: cannot convert value of type 'Bool' to specified type 'Int'
  exit=1

`print(g())` above `func g()` is accepted — the signature was collected before any body:

  $ printf 'print(g())\nfunc g() -> Int { return 1 }\n' > fw.swift
  $ ./lab.exe --typecheck fw.swift; echo "exit=$?"
  exit=0

A function may call itself — `fib` resolves inside its own body:

  $ printf 'func fib(_ n: Int) -> Int {\n  if n < 2 { return n }\n  return fib(n - 1) + fib(n - 2)\n}\nprint(fib(10))\n' > rec.swift
  $ ./lab.exe --typecheck rec.swift; echo "exit=$?"
  exit=0

Two functions may call each other — `isEven` uses `isOdd`, declared after it:

  $ printf 'func isEven(_ n: Int) -> Bool {\n  if n == 0 { return true }\n  return isOdd(n - 1)\n}\nfunc isOdd(_ n: Int) -> Bool {\n  if n == 0 { return false }\n  return isEven(n - 1)\n}\nprint(isEven(4))\n' > mut.swift
  $ ./lab.exe --typecheck mut.swift; echo "exit=$?"
  exit=0

A call in a body to a function declared later in the file resolves the same way:

  $ printf 'func twice(_ n: Int) -> Int { return double(n) }\nfunc double(_ n: Int) -> Int { return n * 2 }\nprint(twice(4))\n' > fw2.swift
  $ ./lab.exe --typecheck fw2.swift; echo "exit=$?"
  exit=0

Redeclaring `f` with a different signature is one redeclaration error, and the later
signature is the one later calls are checked against — `f()` is now an arity error:

  $ printf 'func f() -> Int { return 1 }\nfunc f(_ a: Int) -> Int { return a }\nprint(f())\n' > d2.swift
  $ ./lab.exe --typecheck d2.swift; echo "exit=$?"
  2:1: error: invalid redeclaration of 'f'
  3:7: error: function 'f' expects 1 argument(s) but 0 given
  exit=1
