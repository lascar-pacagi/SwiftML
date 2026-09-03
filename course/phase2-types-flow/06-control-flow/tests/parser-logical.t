`&&` and `||` in the expression grammar, through `--emit-ast`. Their `infix_bp` rows and
`binop_of_kind` arms are GIVEN this time — this file goes green as soon as the lexer makes the
tokens — so what it checks is the precedence the given rows encode.

`&&` binds tighter than `||`: `a && false || a` is `(a && false) || a`:

  $ printf 'let a = true\nlet c = a && false || a\n' > p1.swift
  $ ./lab.exe --emit-ast p1.swift
  (let a true)
  (let c (|| (&& a false) a))

Both sit below the comparisons: `1 < 2 && 3 > 2` compares first:

  $ printf 'let c = 1 < 2 && 3 > 2\n' > p2.swift
  $ ./lab.exe --emit-ast p2.swift
  (let c (&& (< 1 2) (> 3 2)))

And below arithmetic through them: `a + 1 == 2 || b` is `((a + 1) == 2) || b`:

  $ printf 'let a = 1\nlet b = true\nlet c = a + 1 == 2 || b\n' > p3.swift
  $ ./lab.exe --emit-ast p3.swift
  (let a 1)
  (let b true)
  (let c (|| (== (+ a 1) 2) b))

Parentheses override: `a && (false || a)`:

  $ printf 'let a = true\nlet c = a && (false || a)\n' > p4.swift
  $ ./lab.exe --emit-ast p4.swift
  (let a true)
  (let c (&& a (|| false a)))
