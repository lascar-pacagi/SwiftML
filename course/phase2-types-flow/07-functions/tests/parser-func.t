Function declarations and top-level items, through `--emit-ast`. Needs `parse_func` (with
`parse_params` and the `return` arm). A declaration dumps as `(func name (params) -> Ret (body))`,
the arrow part missing when no return type is written.

`func add(_ a: Int, _ b: Int) -> Int { return a + b }` — the whole shape on one line:

  $ printf 'func add(_ a: Int, _ b: Int) -> Int { return a + b }\n' > f1.swift
  $ ./lab.exe --emit-ast f1.swift
  (func add (a:Int b:Int) -> Int ((return (+ a b))))

Without `-> T` the declaration has no return type — `func g() { print(1) }`:

  $ printf 'func g() { print(1) }\n' > f2.swift
  $ ./lab.exe --emit-ast f2.swift
  (func g () ((print 1)))

A body spans lines and holds several statements, in order:

  $ printf 'func f(_ n: Int) -> Int {\n  if n < 2 {\n    return n\n  }\n  let a = f(n - 1)\n  return a + f(n - 2)\n}\n' > f3.swift
  $ ./lab.exe --emit-ast f3.swift
  (func f (n:Int) -> Int ((if (< n 2) ((return n))) (let a (f (- n 1))) (return (+ a (f (- n 2))))))

An empty body — `func nop() { }` — is an empty block:

  $ printf 'func nop() { }\n' > f4.swift
  $ ./lab.exe --emit-ast f4.swift
  (func nop () ())

A program interleaves declarations and statements, keeping source order:

  $ printf 'print(g())\nfunc g() -> Int { return 1 }\nlet x = g()\nfunc h() { }\nprint(x)\n' > f5.swift
  $ ./lab.exe --emit-ast f5.swift
  (print (g ))
  (func g () -> Int ((return 1)))
  (let x (g ))
  (func h () ())
  (print x)

Two declarations in a row, separated by a blank line:

  $ printf 'func a() { }\n\nfunc b() -> Bool {\n  return true\n}\n' > f6.swift
  $ ./lab.exe --emit-ast f6.swift
  (func a () ())
  (func b () -> Bool ((return true)))

`func` with no name is "expected a function name", at the `(`:

  $ printf 'func () { }\n' > e1.swift
  $ ./lab.exe --emit-ast e1.swift; echo "exit=$?"
  1:6: error: expected a function name
  exit=1

An arrow with no type after it — `-> {` — is "expected a return type", at the `{`:

  $ printf 'func f() -> { }\n' > e2.swift
  $ ./lab.exe --emit-ast e2.swift; echo "exit=$?"
  1:13: error: expected a return type
  exit=1

A declaration without a body — `func f() -> Int` then a newline — is "expected '{'" at the
newline (first diagnostic only: the block parser then runs on to the end of input):

  $ printf 'func f() -> Int\nprint(1)\n' > e3.swift
  $ ./lab.exe --emit-ast e3.swift 2>&1 | head -1
  1:16: error: expected '{'

A body that never closes is "expected '}'", reported at end of input:

  $ printf 'func f() {\n  print(1)\n' > e4.swift
  $ ./lab.exe --emit-ast e4.swift; echo "exit=$?"
  3:1: error: expected '}'
  exit=1
