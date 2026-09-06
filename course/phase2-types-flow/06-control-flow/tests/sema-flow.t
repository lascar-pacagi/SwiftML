The control-flow rules, through `--typecheck`. Needs the `TODO(06)` statement arms in
`check_stmt`: Bool conditions, an immutable Int loop variable over an Int range, `break` /
`continue` only inside a loop, and a block as a scope. Wording is swiftc's.

A well-typed program with every construct is silent, exit 0:

  $ printf 'var n = 0\nwhile n < 5 {\n  if n == 2 { n = n + 1 }\n  n = n + 1\n}\nfor i in 0 ..< n {\n  if i == 1 { continue }\n  if i == 3 { break }\n  print(i)\n}\nprint(n)\n' > ok.swift
  $ timeout 5 ./lab.exe --typecheck ok.swift; echo "exit=$?"
  exit=0

`if 1 { }` is "cannot convert value of type 'Int' to specified type 'Bool'", at the condition:

  $ printf 'if 1 {\n  print(1)\n}\n' > c1.swift
  $ timeout 5 ./lab.exe --typecheck c1.swift; echo "exit=$?"
  1:4: error: cannot convert value of type 'Int' to specified type 'Bool'
  exit=1

A `while` condition is checked the same way:

  $ printf 'while "no" {\n  print(1)\n}\n' > c2.swift
  $ timeout 5 ./lab.exe --typecheck c2.swift; echo "exit=$?"
  1:7: error: cannot convert value of type 'String' to specified type 'Bool'
  exit=1

The loop variable is a `let`: `i = 0` inside the body is the constant-assignment error:

  $ printf 'for i in 0 ..< 3 {\n  i = 0\n}\n' > f1.swift
  $ timeout 5 ./lab.exe --typecheck f1.swift; echo "exit=$?"
  2:3: error: cannot assign to value: 'i' is a 'let' constant
  exit=1

The range bounds must be Int: `0.0 ..< 3` is a conversion error on the bound:

  $ printf 'for i in 0.0 ..< 3 {\n  print(i)\n}\n' > f2.swift
  $ timeout 5 ./lab.exe --typecheck f2.swift; echo "exit=$?"
  1:10: error: cannot convert value of type 'Double' to specified type 'Int'
  exit=1

The loop variable is in scope only in the body: `print(i)` after the loop is unknown:

  $ printf 'for i in 0 ..< 3 {\n  print(i)\n}\nprint(i)\n' > f3.swift
  $ timeout 5 ./lab.exe --typecheck f3.swift; echo "exit=$?"
  4:7: error: cannot find 'i' in scope
  exit=1

`break` at top level is "'break' is only allowed inside a loop"; `continue` likewise:

  $ printf 'break\ncontinue\n' > b1.swift
  $ timeout 5 ./lab.exe --typecheck b1.swift; echo "exit=$?"
  1:1: error: 'break' is only allowed inside a loop
  2:1: error: 'continue' is only allowed inside a loop
  exit=1

`break` inside an `if` that is inside a loop is fine — the `if` is not a loop but the `while` is:

  $ printf 'while true {\n  if true {\n    break\n  }\n}\n' > b2.swift
  $ timeout 5 ./lab.exe --typecheck b2.swift; echo "exit=$?"
  exit=0

A name declared in a block dies with the block: `print(z)` after the `if` cannot find it:

  $ printf 'if true {\n  let z = 1\n}\nprint(z)\n' > s1.swift
  $ timeout 5 ./lab.exe --typecheck s1.swift; echo "exit=$?"
  4:7: error: cannot find 'z' in scope
  exit=1

A block sees the names outside it, and assigning an outer `var` from inside works:

  $ printf 'var n = 0\nif true {\n  n = n + 1\n}\nprint(n)\n' > s2.swift
  $ timeout 5 ./lab.exe --typecheck s2.swift; echo "exit=$?"
  exit=0

An inner `let` may shadow an outer name, and the outer one is back after the block:

  $ printf 'let x = 1\nif true {\n  let x = "s"\n  print(x)\n}\nlet y: Int = x\n' > s3.swift
  $ timeout 5 ./lab.exe --typecheck s3.swift; echo "exit=$?"
  exit=0

An `else` block is checked like any other, and gets its own scope:

  $ printf 'var n = 0\nif n == 0 {\n  let a = 1\n  n = a\n} else {\n  let a = "s"\n  print(a)\n}\nprint(n)\n' > s4.swift
  $ timeout 5 ./lab.exe --typecheck s4.swift; echo "exit=$?"
  exit=0

A name from the then-block is not in scope in the else-block — the two are siblings:

  $ printf 'if true {\n  let a = 1\n} else {\n  print(a)\n}\n' > s5.swift
  $ timeout 5 ./lab.exe --typecheck s5.swift; echo "exit=$?"
  4:9: error: cannot find 'a' in scope
  exit=1

Conditions nest: an `if` inside a `while` inside a `for`, each checked in its own scope:

  $ printf 'var s = 0\nfor i in 0 ..< 3 {\n  var j = 0\n  while j < i {\n    if j == 1 {\n      s = s + j\n    }\n    j = j + 1\n  }\n}\nprint(s)\n' > s6.swift
  $ timeout 5 ./lab.exe --typecheck s6.swift; echo "exit=$?"
  exit=0

The loop variable shadows an outer name of the same type, and the outer one is back afterwards:

  $ printf 'var i = 100\nfor i in 0 ..< 3 {\n  print(i)\n}\ni = 7\nprint(i)\n' > s7.swift
  $ timeout 5 ./lab.exe --typecheck s7.swift; echo "exit=$?"
  exit=0

A `break` in a `for` body is fine, and so is one in a `while` nested in a `for`:

  $ printf 'for i in 0 ..< 3 {\n  if i == 1 { break }\n  var j = 0\n  while j < 2 {\n    continue\n  }\n}\n' > b3.swift
  $ timeout 5 ./lab.exe --typecheck b3.swift; echo "exit=$?"
  exit=0

`break` AFTER a loop is outside it again — the depth goes back down:

  $ printf 'while true {\n  break\n}\nbreak\n' > b4.swift
  $ timeout 5 ./lab.exe --typecheck b4.swift; echo "exit=$?"
  4:1: error: 'break' is only allowed inside a loop
  exit=1

The condition of a `while` may use a name the loop itself assigns, and the body may shadow it:

  $ printf 'var n = 3\nwhile n > 0 {\n  let n = "inner"\n  print(n)\n}\n' > s8.swift
  $ timeout 5 ./lab.exe --typecheck s8.swift; echo "exit=$?"
  exit=0

A range bound may be any Int expression, including one using the outer variables:

  $ printf 'let lo = 1\nvar hi = 5\nfor i in lo + 1 ..< hi * 2 {\n  hi = i\n}\nprint(hi)\n' > f4.swift
  $ timeout 5 ./lab.exe --typecheck f4.swift; echo "exit=$?"
  exit=0

Both bounds are checked, so two bad ones report twice:

  $ printf 'for i in "a" ..< true {\n}\n' > f5.swift
  $ timeout 5 ./lab.exe --typecheck f5.swift; echo "exit=$?"
  1:10: error: cannot convert value of type 'String' to specified type 'Int'
  1:18: error: cannot convert value of type 'Bool' to specified type 'Int'
  exit=1

The body is checked even when the bounds are wrong — one run reports everything:

  $ printf 'for i in 0.0 ..< 3 {\n  print(nope)\n}\n' > f6.swift
  $ timeout 5 ./lab.exe --typecheck f6.swift; echo "exit=$?"
  1:10: error: cannot convert value of type 'Double' to specified type 'Int'
  2:9: error: cannot find 'nope' in scope
  exit=1
