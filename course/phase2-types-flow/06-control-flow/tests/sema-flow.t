The control-flow rules, through `--typecheck`. Needs the `TODO(06)` statement arms in
`check_stmt`: Bool conditions, an immutable Int loop variable over an Int range, `break` /
`continue` only inside a loop, and a block as a scope. Wording is swiftc's.

A well-typed program with every construct is silent, exit 0:

  $ printf 'var n = 0\nwhile n < 5 {\n  if n == 2 { n = n + 1 }\n  n = n + 1\n}\nfor i in 0 ..< n {\n  if i == 1 { continue }\n  if i == 3 { break }\n  print(i)\n}\nprint(n)\n' > ok.swift
  $ ./lab.exe --typecheck ok.swift; echo "exit=$?"
  exit=0

`if 1 { }` is "cannot convert value of type 'Int' to specified type 'Bool'", at the condition:

  $ printf 'if 1 {\n  print(1)\n}\n' > c1.swift
  $ ./lab.exe --typecheck c1.swift; echo "exit=$?"
  1:4: error: cannot convert value of type 'Int' to specified type 'Bool'
  exit=1

A `while` condition is checked the same way:

  $ printf 'while "no" {\n  print(1)\n}\n' > c2.swift
  $ ./lab.exe --typecheck c2.swift; echo "exit=$?"
  1:7: error: cannot convert value of type 'String' to specified type 'Bool'
  exit=1

The loop variable is a `let`: `i = 0` inside the body is the constant-assignment error:

  $ printf 'for i in 0 ..< 3 {\n  i = 0\n}\n' > f1.swift
  $ ./lab.exe --typecheck f1.swift; echo "exit=$?"
  2:3: error: cannot assign to value: 'i' is a 'let' constant
  exit=1

The range bounds must be Int: `0.0 ..< 3` is a conversion error on the bound:

  $ printf 'for i in 0.0 ..< 3 {\n  print(i)\n}\n' > f2.swift
  $ ./lab.exe --typecheck f2.swift; echo "exit=$?"
  1:10: error: cannot convert value of type 'Double' to specified type 'Int'
  exit=1

The loop variable is in scope only in the body: `print(i)` after the loop is unknown:

  $ printf 'for i in 0 ..< 3 {\n  print(i)\n}\nprint(i)\n' > f3.swift
  $ ./lab.exe --typecheck f3.swift; echo "exit=$?"
  4:7: error: cannot find 'i' in scope
  exit=1

`break` at top level is "'break' is only allowed inside a loop"; `continue` likewise:

  $ printf 'break\ncontinue\n' > b1.swift
  $ ./lab.exe --typecheck b1.swift; echo "exit=$?"
  1:1: error: 'break' is only allowed inside a loop
  2:1: error: 'continue' is only allowed inside a loop
  exit=1

`break` inside an `if` that is inside a loop is fine — the `if` is not a loop but the `while` is:

  $ printf 'while true {\n  if true {\n    break\n  }\n}\n' > b2.swift
  $ ./lab.exe --typecheck b2.swift; echo "exit=$?"
  exit=0

A name declared in a block dies with the block: `print(z)` after the `if` cannot find it:

  $ printf 'if true {\n  let z = 1\n}\nprint(z)\n' > s1.swift
  $ ./lab.exe --typecheck s1.swift; echo "exit=$?"
  4:7: error: cannot find 'z' in scope
  exit=1

A block sees the names outside it, and assigning an outer `var` from inside works:

  $ printf 'var n = 0\nif true {\n  n = n + 1\n}\nprint(n)\n' > s2.swift
  $ ./lab.exe --typecheck s2.swift; echo "exit=$?"
  exit=0

An inner `let` may shadow an outer name, and the outer one is back after the block:

  $ printf 'let x = 1\nif true {\n  let x = "s"\n  print(x)\n}\nlet y: Int = x\n' > s3.swift
  $ ./lab.exe --typecheck s3.swift; echo "exit=$?"
  exit=0
