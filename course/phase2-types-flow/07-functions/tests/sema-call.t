Calls to user functions, through `--typecheck`. Needs the `Some (ptypes, ret)` arm of
`infer_call` (with the driver, `check_func` and `return`, so the callees themselves check):
arity, then each argument against its parameter type, and the callee's return type as the
result. The arity wording is ours; the argument wording is `check_expr`'s.

`add(1, 2)` on `func add(_ a: Int, _ b: Int) -> Int` is an `Int` — usable as one:

  $ printf 'func add(_ a: Int, _ b: Int) -> Int { return a + b }\nlet s: Int = add(1, 2)\nprint(add(s, 3) * 2)\n' > ok1.swift
  $ ./lab.exe --typecheck ok1.swift; echo "exit=$?"
  exit=0

A call may appear anywhere an expression can — as an argument, a condition, a bound:

  $ printf 'func inc(_ n: Int) -> Int { return n + 1 }\nfunc pos(_ n: Int) -> Bool { return n > 0 }\nprint(inc(inc(1)))\nif pos(inc(0)) { print(1) }\nfor i in 0 ..< inc(2) { print(i) }\n' > ok2.swift
  $ ./lab.exe --typecheck ok2.swift; echo "exit=$?"
  exit=0

A `Void` function is called as a statement; `f()` with no parameters takes no arguments:

  $ printf 'func hello() { print(1) }\nhello()\n' > ok3.swift
  $ ./lab.exe --typecheck ok3.swift; echo "exit=$?"
  exit=0

An integer literal argument coerces to a `Double` parameter, as at a `let`:

  $ printf 'func half(_ x: Double) -> Double { return x / 2 }\nprint(half(3))\n' > ok4.swift
  $ ./lab.exe --typecheck ok4.swift; echo "exit=$?"
  exit=0

`f(1, 2)` on a one-parameter `f` is "function 'f' expects 1 argument(s) but 2 given":

  $ printf 'func f(_ x: Int) -> Int { return x }\nprint(f(1, 2))\n' > a1.swift
  $ ./lab.exe --typecheck a1.swift; echo "exit=$?"
  2:7: error: function 'f' expects 1 argument(s) but 2 given
  exit=1

Too few is the same message — `f()` on a one-parameter `f`:

  $ printf 'func f(_ x: Int) -> Int { return x }\nprint(f())\n' > a2.swift
  $ ./lab.exe --typecheck a2.swift; echo "exit=$?"
  2:7: error: function 'f' expects 1 argument(s) but 0 given
  exit=1

An argument to a parameterless function is an arity error too:

  $ printf 'func f() -> Int { return 1 }\nprint(f(1))\n' > a3.swift
  $ ./lab.exe --typecheck a3.swift; echo "exit=$?"
  2:7: error: function 'f' expects 0 argument(s) but 1 given
  exit=1

On an arity error the arguments are not checked against anything — one message, not two:

  $ printf 'func f(_ x: Int) -> Int { return x }\nprint(f("a", "b"))\n' > a4.swift
  $ ./lab.exe --typecheck a4.swift; echo "exit=$?"
  2:7: error: function 'f' expects 1 argument(s) but 2 given
  exit=1

`f("s")` on `f(_ x: Int)` is a conversion error, at the argument:

  $ printf 'func f(_ x: Int) -> Int { return x }\nprint(f("s"))\n' > t1.swift
  $ ./lab.exe --typecheck t1.swift; echo "exit=$?"
  2:9: error: cannot convert value of type 'String' to specified type 'Int'
  exit=1

Each argument is checked against its own parameter — two wrong ones give two errors:

  $ printf 'func f(_ a: Int, _ b: Bool) { }\nf(true, 1)\n' > t2.swift
  $ ./lab.exe --typecheck t2.swift; echo "exit=$?"
  2:3: error: cannot convert value of type 'Bool' to specified type 'Int'
  2:9: error: cannot convert value of type 'Int' to specified type 'Bool'
  exit=1

The result has the declared type: an `Int` result annotated `String` is a conversion error:

  $ printf 'func f() -> Int { return 1 }\nlet s: String = f()\n' > r1.swift
  $ ./lab.exe --typecheck r1.swift; echo "exit=$?"
  2:17: error: cannot convert value of type 'Int' to specified type 'String'
  exit=1

A `Void` result is `()`: binding it as an `Int`, or adding to it, is rejected:

  $ printf 'func f() { }\nlet v: Int = f()\nlet w = f() + 1\n' > r2.swift
  $ ./lab.exe --typecheck r2.swift; echo "exit=$?"
  2:14: error: cannot convert value of type '()' to specified type 'Int'
  3:9: error: binary operator '+' cannot be applied to operands of type '()' and 'Int'
  exit=1

A wrong argument inside a nested call is reported once, at the inner call:

  $ printf 'func f(_ x: Int) -> Int { return x }\nprint(f(f(true)))\n' > n1.swift
  $ ./lab.exe --typecheck n1.swift; echo "exit=$?"
  2:11: error: cannot convert value of type 'Bool' to specified type 'Int'
  exit=1

A call to a name that is not a function is still "cannot find 'nope' in scope":

  $ printf 'print(nope(1))\n' > u1.swift
  $ ./lab.exe --typecheck u1.swift; echo "exit=$?"
  1:7: error: cannot find 'nope' in scope
  exit=1
