The definite-return analysis, through `--emit-returns`, which parses a program and asks
`Sema.block_returns` about each function's body — `Sema.check` never runs, so these cases need
that one hole and no other: the two-pass driver, `check_func`, `return` and call typing may all
still be TODO while this file goes green. (It does need the parser, since the input is source.)
Answers are per function, in declaration order.

A body whose statement is a `return` returns:

  $ printf 'func f() -> Int { return 1 }\n' > r1.swift
  $ ./lab.exe --emit-returns r1.swift
  f: returns

A body that never mentions `return` does not:

  $ printf 'func f() -> Int { print(1) }\n' > r2.swift
  $ ./lab.exe --emit-returns r2.swift
  f: does not return

An `if` with no `else` does not return: nothing is known about the path where the condition is
false:

  $ printf 'func f() -> Int {\n  if 1 < 2 { return 1 }\n}\n' > r3.swift
  $ ./lab.exe --emit-returns r3.swift
  f: does not return

An `if`/`else` returns when BOTH blocks do — every path is then covered:

  $ printf 'func f() -> Int {\n  if 1 < 2 { return 1 } else { return 2 }\n}\n' > r4.swift
  $ ./lab.exe --emit-returns r4.swift
  f: returns

One arm is not enough — an `else` that falls through leaves a path with no value:

  $ printf 'func f() -> Int {\n  if 1 < 2 { return 1 } else { print(2) }\n}\n' > r5.swift
  $ ./lab.exe --emit-returns r5.swift
  f: does not return

An `else if` chain is an `if` inside an `else`, so the recursion decides it: with a final `else`
that returns, every path returns:

  $ printf 'func f() -> Int {\n  if 1 < 2 { return 1 } else if 2 < 3 { return 2 } else { return 3 }\n}\n' > r6.swift
  $ ./lab.exe --emit-returns r6.swift
  f: returns

The same chain without that final `else` does not — the last condition may be false:

  $ printf 'func f() -> Int {\n  if 1 < 2 { return 1 } else if 2 < 3 { return 2 }\n}\n' > r7.swift
  $ ./lab.exe --emit-returns r7.swift
  f: does not return

A `return` inside a `while` proves nothing, because the loop may run zero times — this is the
case that is wrong if you match on statements without thinking about execution:

  $ printf 'func f() -> Int {\n  while 1 < 2 { return 1 }\n}\n' > r8.swift
  $ ./lab.exe --emit-returns r8.swift
  f: does not return

A `for` is the same — its range may be empty:

  $ printf 'func f() -> Int {\n  for i in 0 ..< 3 { return i }\n}\n' > r9.swift
  $ ./lab.exe --emit-returns r9.swift
  f: does not return

A loop followed by a `return` does return — the `return` is what settles it, not the loop:

  $ printf 'func f() -> Int {\n  while 1 < 2 { print(1) }\n  return 0\n}\n' > r10.swift
  $ ./lab.exe --emit-returns r10.swift
  f: returns

A `return` with statements after it still returns: whatever follows is unreachable (swiftc agrees,
and warns that the code will never be executed):

  $ printf 'func f() -> Int {\n  return 1\n  print(2)\n}\n' > r11.swift
  $ ./lab.exe --emit-returns r11.swift
  f: returns

Each function is answered on its own. `c` has an empty body, so it does not return — the analysis
says only what the body does; whether that MATTERS is `check_func`'s business, and it asks only
about functions with a return type:

  $ printf 'func a() -> Int { return 1 }\nfunc b() -> Int { print(1) }\nfunc c() { }\n' > r12.swift
  $ ./lab.exe --emit-returns r12.swift
  a: returns
  b: does not return
  c: does not return
