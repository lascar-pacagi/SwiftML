Typing `&&` and `||`, through `--typecheck`. Needs the `TODO(06)` arm in `infer_binary`.

Two Bool operands give a Bool, usable wherever a Bool is expected:

  $ printf 'let a = true\nlet b: Bool = a && false || true\n' > ok.swift
  $ ./lab.exe --typecheck ok.swift; echo "exit=$?"
  exit=0

Comparisons feed them, since a comparison is a Bool:

  $ printf 'let n = 3\nlet b = n > 1 && n < 5\n' > ok2.swift
  $ ./lab.exe --typecheck ok2.swift; echo "exit=$?"
  exit=0

`1 && true` is rejected with the two-types wording, at the start of the expression:

  $ printf 'let b = 1 && true\n' > e1.swift
  $ ./lab.exe --typecheck e1.swift; echo "exit=$?"
  1:9: error: binary operator '&&' cannot be applied to operands of type 'Int' and 'Bool'
  exit=1

`1 || 2` — both sides Int — gets the "two 'Int' operands" wording:

  $ printf 'let b = 1 || 2\n' > e2.swift
  $ ./lab.exe --typecheck e2.swift; echo "exit=$?"
  1:9: error: binary operator '||' cannot be applied to two 'Int' operands
  exit=1

`let b: Int = true && false` types the operator fine and fails the annotation: ONE error,
the conversion, at the expression:

  $ printf 'let b: Int = true && false\n' > e3.swift
  $ ./lab.exe --typecheck e3.swift; echo "exit=$?"
  1:14: error: cannot convert value of type 'Bool' to specified type 'Int'
  exit=1
