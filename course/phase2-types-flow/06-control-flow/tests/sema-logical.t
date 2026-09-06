Typing `&&` and `||`, through `--typecheck`. Needs the `TODO(06)` arm in `infer_binary`.

Two Bool operands give a Bool, usable wherever a Bool is expected:

  $ printf 'let a = true\nlet b: Bool = a && false || true\n' > ok.swift
  $ timeout 5 ./lab.exe --typecheck ok.swift; echo "exit=$?"
  exit=0

Comparisons feed them, since a comparison is a Bool:

  $ printf 'let n = 3\nlet b = n > 1 && n < 5\n' > ok2.swift
  $ timeout 5 ./lab.exe --typecheck ok2.swift; echo "exit=$?"
  exit=0

`1 && true` is rejected with the two-types wording, at the start of the expression:

  $ printf 'let b = 1 && true\n' > e1.swift
  $ timeout 5 ./lab.exe --typecheck e1.swift; echo "exit=$?"
  1:9: error: binary operator '&&' cannot be applied to operands of type 'Int' and 'Bool'
  exit=1

`1 || 2` — both sides Int — gets the "two 'Int' operands" wording:

  $ printf 'let b = 1 || 2\n' > e2.swift
  $ timeout 5 ./lab.exe --typecheck e2.swift; echo "exit=$?"
  1:9: error: binary operator '||' cannot be applied to two 'Int' operands
  exit=1

`let b: Int = true && false` types the operator fine and fails the annotation: ONE error,
the conversion, at the expression:

  $ printf 'let b: Int = true && false\n' > e3.swift
  $ timeout 5 ./lab.exe --typecheck e3.swift; echo "exit=$?"
  1:14: error: cannot convert value of type 'Bool' to specified type 'Int'
  exit=1

`&&` chains and mixes with `||`, and the whole thing is still one Bool:

  $ printf 'let a = true\nlet b: Bool = a && a && a || a && a\n' > ok3.swift
  $ timeout 5 ./lab.exe --typecheck ok3.swift; echo "exit=$?"
  exit=0

An operand may be any Bool-valued expression — a comparison, a parenthesised logical, a variable
(there is no `!` in this subset, so a negated test is written `== false`):

  $ printf 'let n = 3\nlet f = false\nlet b = (n > 1 || f) && (n == 0) == false\n' > ok4.swift
  $ timeout 5 ./lab.exe --typecheck ok4.swift; echo "exit=$?"
  exit=0

A Double operand is rejected like any other non-Bool, naming both types:

  $ printf 'let b = 1.5 && true\n' > e4.swift
  $ timeout 5 ./lab.exe --typecheck e4.swift; echo "exit=$?"
  1:9: error: binary operator '&&' cannot be applied to operands of type 'Double' and 'Bool'
  exit=1

A String pair gets the two-operands wording, since both sides agree:

  $ printf 'let b = "a" || "b"\n' > e5.swift
  $ timeout 5 ./lab.exe --typecheck e5.swift; echo "exit=$?"
  1:9: error: binary operator '||' cannot be applied to two 'String' operands
  exit=1

Both operands are checked, so two bad ones report twice in one run:

  $ printf 'let b = 1 && 2\nlet c = "x" && true\n' > e6.swift
  $ timeout 5 ./lab.exe --typecheck e6.swift; echo "exit=$?"
  1:9: error: binary operator '&&' cannot be applied to two 'Int' operands
  2:9: error: binary operator '&&' cannot be applied to operands of type 'String' and 'Bool'
  exit=1

The result feeds a condition directly — that is the whole point of the operator:

  $ printf 'let n = 3\nif n > 1 && n < 5 {\n  print(n)\n}\n' > ok5.swift
  $ timeout 5 ./lab.exe --typecheck ok5.swift; echo "exit=$?"
  exit=0
