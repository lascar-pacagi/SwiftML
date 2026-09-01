`e as T` type-checking, through `--typecheck`. This is `TODO(05g)`, the one rule where `infer`
calls `check_expr` — the type is written down, so there is nothing to synthesise.

`1 as Double` is accepted: the literal is CHECKED against the written type.
Synthesis would have committed `1 : Int` and then complained. Checking pushes `Double` into the
literal instead, which is the whole point of the second judgment:

  $ printf 'let a: Double = 1 as Double\nprint(a)\n' > s1.swift
  $ ./lab.exe --typecheck s1.swift >/dev/null 2>&1; echo "exit=$?"
  exit=0

`i as Double` is rejected: a variable of type Int does not flex.
Same asymmetry as the annotation rule, reached through a different construct — and swiftc rejects
it too, wording it "cannot convert value of type 'Int' to type 'Double' in coercion":

  $ printf 'let i = 1\nlet y = i as Double\n' > s2.swift
  $ ./lab.exe --typecheck s2.swift 2>&1; echo "exit=$?"
  2:9: error: cannot convert value of type 'Int' to specified type 'Double'
  exit=1

`"s" as Int` is rejected, and `1 as Foo` cannot find the type.
The first is the ordinary check failing; the second is `Types.of_name` returning None, the same
`None` that makes an unknown annotation fail:

  $ printf 'let z = "s" as Int\n' > s3.swift
  $ ./lab.exe --typecheck s3.swift 2>&1; echo "exit=$?"
  1:9: error: cannot convert value of type 'String' to specified type 'Int'
  exit=1

  $ printf 'let u = 1 as Foo\n' > s4.swift
  $ ./lab.exe --typecheck s4.swift 2>&1; echo "exit=$?"
  1:9: error: cannot find type 'Foo' in scope
  exit=1
