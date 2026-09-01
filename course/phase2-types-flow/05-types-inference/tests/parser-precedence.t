Operator precedence, through `--emit-ast`. Needs the `TODO(05)` row in `infix_bp`; the Pratt loop
itself is given. The dump is fully parenthesised, so the tree shape is visible.

All six comparison tokens map to their own `Ast` operator.
`binop_of_kind` is a six-row table and a copy-paste slip in it — `!=` yielding `Ast.Eq`, say —
would still parse, still type-check, and only show up as a wrong answer at runtime. The dump names
the operator, so each row is checked separately:

  $ printf 'let a = 1 == 2\nlet b = 1 != 2\nlet c = 1 < 2\nlet d = 1 <= 2\nlet e = 1 > 2\nlet f = 1 >= 2\n' > q0.swift
  $ ./lab.exe --emit-ast q0.swift
  (let a (== 1 2))
  (let b (!= 1 2))
  (let c (< 1 2))
  (let d (<= 1 2))
  (let e (> 1 2))
  (let f (>= 1 2))

`1 + 2 < 3 * 4` groups as `(1 + 2) < (3 * 4)`.
Comparisons bind LOOSER than arithmetic, so each side of the `<` is finished before the
comparison is applied — without that, `1 + (2 < 3) * 4` would come out instead:

  $ printf 'let a = 1 + 2 < 3 * 4\n' > q1.swift
  $ ./lab.exe --emit-ast q1.swift
  (let a (< (+ 1 2) (* 3 4)))

`*` still binds tighter than `+`, which still binds tighter than `<`.
Three levels in one expression, each side of the comparison built separately:

  $ printf 'let b = 1 * 2 + 3 < 4 - 5\n' > q2.swift
  $ ./lab.exe --emit-ast q2.swift
  (let b (< (+ (* 1 2) 3) (- 4 5)))

Comparisons are left-associative here: `1 < 2 == true` is `(1 < 2) == true`.
Swift makes comparisons NON-associative and rejects `a < b < c`; ours chains, which §6's first
exercise fixes:

  $ printf 'let c = 1 < 2 == true\n' > q3.swift
  $ ./lab.exe --emit-ast q3.swift
  (let c (== (< 1 2) true))

Parentheses still win: `(1 + 2) * 3 >= 9`.
The `(` prefix parses a sub-expression at binding power 0, so the grouping is explicit:

  $ printf 'let d = (1 + 2) * 3 >= 9\n' > q4.swift
  $ ./lab.exe --emit-ast q4.swift
  (let d (>= (* (+ 1 2) 3) 9))

Prefix `-` and `%` bind tighter than a comparison too.
Unary minus is not in the `infix_bp` table at all — it is handled in the prefix position with its
own binding power — and `%` sits with `*` and `/` at 20:

  $ printf 'let g = -1 < 2\nlet h = 7 %% 2 == 1\n' > q5.swift
  $ ./lab.exe --emit-ast q5.swift
  (let g (< (- 1) 2))
  (let h (== (% 7 2) 1))
