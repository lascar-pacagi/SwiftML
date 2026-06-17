End-to-end via the `./lab.exe` binary: --emit-ast for the new syntax, --typecheck for the
type checker. RED until lexer/parser/sema are implemented.

The new literals and a type annotation parse into the AST:

  $ printf 'let d: Double = 3.14\nlet b = true\nlet s = "hi"\n' > a.swift
  $ ./lab.exe --emit-ast a.swift
  (let d : Double 3.14)
  (let b true)
  (let s "hi")

Comparison operators bind looser than arithmetic:

  $ printf 'let c = 1 + 2 < 3 * 4\n' > c.swift
  $ ./lab.exe --emit-ast c.swift
  (let c (< (+ 1 2) (* 3 4)))

A well-typed program type-checks with no diagnostics (exit 0). Note the integer-literal
coercion in `1 + 2` against the Double annotation, and a reassigned var:

  $ printf 'let d: Double = 1 + 2\nvar n = 1\nn = 2\nprint(d)\n' > ok.swift
  $ ./lab.exe --typecheck ok.swift >out.txt 2>err.txt; echo "exit=$?"
  exit=0
  $ test -s err.txt && cat err.txt || echo "no diagnostics"
  no diagnostics

Ill-typed programs are rejected (nonzero) with the matching diagnostic:

  $ printf 'let x: Int = "s"\n' > b1.swift
  $ ./lab.exe --typecheck b1.swift 2>&1 | grep -o "cannot convert value of type 'String' to specified type 'Int'" || true
  cannot convert value of type 'String' to specified type 'Int'

  $ printf 'let y = 1 + true\n' > b2.swift
  $ ./lab.exe --typecheck b2.swift 2>&1 | grep -o "cannot be applied to operands of type 'Int' and 'Bool'" || true
  cannot be applied to operands of type 'Int' and 'Bool'

  $ printf 'let i = 1\nlet d: Double = i\n' > b3.swift
  $ ./lab.exe --typecheck b3.swift >/dev/null 2>&1; echo "exit=$?"
  exit=1
