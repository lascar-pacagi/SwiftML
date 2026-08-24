Checks the AST `swiftml --emit-ast` builds — precedence and associativity are the point.

RED until you implement `parser.ml` (in the concept directory). Refresh golden output with `dune promote`.

Precedence: `*` binds tighter than `+`:

  $ printf 'print(1 + 2 * 3)\n' > a.swift
  $ swiftml --emit-ast a.swift
  (print (+ 1 (* 2 3)))

Parentheses override precedence (and nest):

  $ printf 'print(((1 + 2)) * 3)\n' > b.swift
  $ swiftml --emit-ast b.swift
  (print (* (+ 1 2) 3))

Left associativity of `-`:

  $ printf 'print(10 - 4 - 3)\n' > c.swift
  $ swiftml --emit-ast c.swift
  (print (- (- 10 4) 3))

`/` and `%` share the high precedence level and are left-associative; `+` is lower:

  $ printf 'print(1 + 20 / 4 %% 3)\n' > d.swift
  $ swiftml --emit-ast d.swift
  (print (+ 1 (% (/ 20 4) 3)))

Unary minus: it binds tighter than any binary operator, so it wraps just its operand:

  $ printf 'print(-5 + 8)\n' > e.swift
  $ swiftml --emit-ast e.swift
  (print (+ (- 5) 8))

  $ printf 'print(2 * -3)\n' > f.swift
  $ swiftml --emit-ast f.swift
  (print (* 2 (- 3)))

let/var bindings and variable references:

  $ printf 'let a = 6\nvar c = a + 7\n' > g.swift
  $ swiftml --emit-ast g.swift
  (let a 6)
  (var c (+ a 7))

Reassignment is its own statement (distinct from a binding and from an expression
statement — it needs one token of lookahead past the identifier to see the `=`):

  $ printf 'var c = 1\nc = c * 2\n' > h.swift
  $ swiftml --emit-ast h.swift
  (var c 1)
  (= c (* c 2))

A malformed program is REPORTED, not silently accepted: diagnostics go to stderr as
`line:col: error: …` and the compile fails. The wording is yours (§6 exercise 1 improves
it), so this checks the shape only.

  $ printf 'let a = 1\nlet b = *\nprint(a)\n' > bad.swift
  $ swiftml --emit-ast bad.swift 2>&1 >/dev/null | grep -q 'error:' && echo reported
  reported
  $ swiftml --emit-ast bad.swift > /dev/null 2>&1; echo "exit=$?"
  exit=1
