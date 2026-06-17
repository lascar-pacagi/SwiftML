Macros: a compile-time AST -> AST expander that runs BEFORE the type checker.
RED until the TODO(40) holes (the macro expansion rules: #line/#column and #assert).

`#line` / `#column` expand to integer literals — the source location, like swiftc's magic literals:

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

Macros nest inside ordinary expressions (they expanded before sema even looked):

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

`#assert(cond)` expands to a conditional trap — it passes silently when true and traps (exit 133)
when false, exactly like swiftc's `assert`:

  $ cat > c.swift <<'SWIFT'
  > let x = 5
  > #assert(x > 0)
  > #assert(x > 10)
  > print(99)
  > SWIFT
  $ ./lab.exe build c.swift -o c
  $ sh -c './c; echo exit=$?' 2>/dev/null
  exit=133

An unknown macro is rejected by the type checker (it survived expansion):

  $ cat > bad.swift <<'SWIFT'
  > print(#nope)
  > SWIFT
  $ ./lab.exe --typecheck bad.swift
  1:7: error: unknown macro '#nope'
  [1]
