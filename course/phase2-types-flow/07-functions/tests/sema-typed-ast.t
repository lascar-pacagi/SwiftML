What the checker PRODUCES for functions, through `--emit-tast`. Two things get resolved here that
`Ast` could not express: a call's identity, and a signature's types.

`Ast.Call (f, args)` is three different things — print, a declared function, or an unknown name —
and only the checker can tell which. The tree records the answer as a different node, so nothing
downstream re-decides. A signature's written type NAMES are gone too: `n:Int` below is the
resolved type, not the string "Int":

  $ printf 'func twice(_ n: Int) -> Int {\n  return n * 2\n}\nprint(twice(21))\n' > f1.swift
  $ ./lab.exe --emit-tast f1.swift
  (func twice (n:Int) -> Int {(return (* (local n : Int) (int_lit 2 : Int) : Int))})
  (print (call twice (int_lit 21 : Int) : Int) : ())

The same source with a Double parameter produces a tree that differs in exactly one place — the
type the literal `2` carries. Nothing in the program text changed; what changed is what the
checker concluded, and because it wrote that down, no later stage has to work it out again. This
is the whole point of PLAN.md §0.1, visible in one line:

  $ printf 'func scale(_ x: Double) -> Double {\n  return x * 2\n}\nprint(scale(1.5))\n' > f2.swift
  $ ./lab.exe --emit-tast f2.swift
  (func scale (x:Double) -> Double {(return (* (local x : Double) (int_lit 2 : Double) : Double))})
  (print (call scale (double_lit 1.5 : Double) : Double) : ())

A call to a name that is not a function and not print is rejected, so no tree is produced:

  $ printf 'print(nope(1))\n' > f3.swift
  $ ./lab.exe --emit-tast f3.swift 2>&1; echo "exit=$?"
  1:7: error: cannot find 'nope' in scope
  print(nope(1))
        ^
  exit=1
