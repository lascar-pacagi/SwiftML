TODO(40a) — expression macros. `#line` and `#column` are Swift's *magic identifiers*: they stand
for the position they were WRITTEN at, and the expander replaces each with an integer literal
before the type checker ever runs. Everything downstream sees an ordinary `Int`.

Each `#line` is the line it appears on, so three of them on three lines give three numbers.

  $ cat > a.swift <<'SWIFT'
  > print(#line)
  > print(#line)
  > func f() { print(#line) }
  > f()
  > SWIFT
  $ ./lab.exe build a.swift -o a && ./a
  1
  2
  3
  $ swiftc -Onone a.swift -o a_sw && ./a_sw
  1
  2
  3

`#column` is the column of the `#`, one-based — so moving the macro right moves the number, and
the number does not depend on where the value is later printed.

  $ cat > col.swift <<'SWIFT'
  > print(#column)
  > print(  #column)
  > let c = #column
  > print(c)
  > SWIFT
  $ ./lab.exe build col.swift -o col && ./col
  7
  9
  9
  $ swiftc -Onone col.swift -o col_sw && ./col_sw
  7
  9
  9

Expansion is an ordinary AST rewrite, so a macro nests wherever an expression may: in
arithmetic, on the right of a `let`, inside a `return`.

  $ cat > b.swift <<'SWIFT'
  > print(#line + 100)
  > let x = #line
  > print(x)
  > func g() -> Int { return #line }
  > print(g())
  > SWIFT
  $ ./lab.exe build b.swift -o b && ./b
  101
  2
  4

The walk has to reach every body in the program, and a STRUCT method is one — a `#line` there
used to survive expansion and get rejected as an unknown macro.

  $ cat > sm.swift <<'SWIFT'
  > struct S {
  >   var x: Int
  >   func at() -> Int { return #line }
  > }
  > let s = S(x: 1)
  > print(s.at())
  > print(#line)
  > SWIFT
  $ ./lab.exe build sm.swift -o sm && ./sm
  3
  7
  $ swiftc -Onone sm.swift -o sm_sw && ./sm_sw
  3
  7

`--emit-ast` is the PARSER's output, so the macro is still there — it is the one view of the
program taken before the expander runs. Everything after it (sema, SILGen, both backends) sees
only what the expansion left behind, which is why no other stage has a rule for `#line` at all.
That the AST really does still carry a `MacroExpr`, and really does not after expansion, is
checked directly on the tree by `test_macros.ml`.

  $ ./lab.exe --emit-ast b.swift | head -2
  (print (+ (macro #line ) 100))
  (let x (macro #line ))

The expansion is what makes the numbers above possible: a macro is replaced by a literal of the
position it was WRITTEN at, not of where its value is eventually used. Moving the use to another
line does not change it, and two uses on one line agree.

  $ cat > moved.swift <<'SWIFT'
  > let a = #line
  > print(a)
  > print(a)
  > let b = #line
  > let c = #line
  > print(b)
  > print(c)
  > SWIFT
  $ ./lab.exe build moved.swift -o moved && ./moved
  1
  1
  4
  5
  $ swiftc -Onone moved.swift -o moved_sw && ./moved_sw
  1
  1
  4
  5

An UNKNOWN macro is deliberately left in place rather than guessed at, so the type checker is
the one to reject it — one error, at the `#`.

  $ printf 'print(#nope)\n' > bad.swift
  $ ./lab.exe --typecheck bad.swift
  1:7: error: unknown macro '#nope'
  [1]
