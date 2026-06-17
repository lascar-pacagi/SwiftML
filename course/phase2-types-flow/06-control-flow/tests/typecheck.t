End-to-end via `./lab.exe`: --emit-ast for the control-flow syntax, --typecheck for the rules.
RED until the lexer/parser/sema TODO(06) holes are filled.

Control flow parses into the AST (a block is a parenthesised statement list):

  $ printf 'var n = 0\nwhile n < 3 {\n  n = n + 1\n}\nif n == 3 {\n  print(n)\n} else {\n  print(0)\n}\nfor i in 0 ..< n {\n  print(i)\n}\n' > a.swift
  $ ./lab.exe --emit-ast a.swift
  (var n 0)
  (while (< n 3) ((= n (+ n 1))))
  (if (== n 3) ((print n)) ((print 0)))
  (for i 0 n ((print i)))

`&&` binds tighter than `||`, both below comparison:

  $ printf 'let a = true\nlet c = a && false || a\n' > b.swift
  $ ./lab.exe --emit-ast b.swift
  (let a true)
  (let c (|| (&& a false) a))

A well-typed control-flow program type-checks (exit 0):

  $ printf 'var n = 0\nwhile n < 5 {\n  if n == 2 { n = n + 1 }\n  n = n + 1\n}\nprint(n)\n' > ok.swift
  $ ./lab.exe --typecheck ok.swift >out.txt 2>err.txt; echo "exit=$?"
  exit=0
  $ test -s err.txt && cat err.txt || echo "no diagnostics"
  no diagnostics

Ill-formed control flow is rejected with the matching diagnostic:

  $ printf 'if 1 {\n  print(1)\n}\n' > c1.swift
  $ ./lab.exe --typecheck c1.swift 2>&1 | grep -o "cannot convert value of type 'Int' to specified type 'Bool'" || true
  cannot convert value of type 'Int' to specified type 'Bool'

  $ printf 'break\n' > c2.swift
  $ ./lab.exe --typecheck c2.swift 2>&1 | grep -o "'break' is only allowed inside a loop" || true
  'break' is only allowed inside a loop

  $ printf 'if true {\n  let z = 1\n}\nprint(z)\n' > c3.swift
  $ ./lab.exe --typecheck c3.swift 2>&1 | grep -o "cannot find 'z' in scope" || true
  cannot find 'z' in scope
