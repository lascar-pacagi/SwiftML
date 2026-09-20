Expressions on their own, through `./lab.exe --emit-expr`, which parses the file as ONE
expression with `parse_expr` — so this needs only `TODO(02a)` (the Pratt loop and the call
arguments), not the statement or program holes. RED until 02a is written.

`1 + 2 * 3` groups as `1 + (2 * 3)`: `*` binds tighter than `+`.
The dump is fully parenthesised, so the tree shape is what you read:

  $ printf '1 + 2 * 3\n' > a.swift
  $ ./lab.exe --emit-expr a.swift
  (+ 1 (* 2 3))

`((1 + 2)) * 3` groups as `(1 + 2) * 3`: parentheses win, and nest.

  $ printf '((1 + 2)) * 3\n' > b.swift
  $ ./lab.exe --emit-expr b.swift
  (* (+ 1 2) 3)

`10 - 4 - 3` groups as `(10 - 4) - 3`: `-` is left-associative.
Right-associative would give `10 - (4 - 3) = 9`; Swift, like C, makes it `3`:

  $ printf '10 - 4 - 3\n' > c.swift
  $ ./lab.exe --emit-expr c.swift
  (- (- 10 4) 3)

`1 + 20 / 4 % 3` is `1 + ((20 / 4) % 3)`: `/` and `%` sit one level above `+`.

  $ printf '1 + 20 / 4 %% 3\n' > d.swift
  $ ./lab.exe --emit-expr d.swift
  (+ 1 (% (/ 20 4) 3))

`-5 + 8` is `(-5) + 8`, `2 * -3` is `2 * (-3)`: unary minus takes one operand.
It binds tighter than every binary operator, and it is a PREFIX: it can follow `*`.

  $ printf -- '-5 + 8\n' > e.swift
  $ ./lab.exe --emit-expr e.swift
  (+ (- 5) 8)

  $ printf '2 * -3\n' > f.swift
  $ ./lab.exe --emit-expr f.swift
  (* 2 (- 3))

`print(1, 2 + 3)` carries its arguments in source order.
`parse_call_args` reads zero or more comma-separated expressions; the dump lists them:

  $ printf 'print(1, 2 + 3)\n' > g.swift
  $ ./lab.exe --emit-expr g.swift
  (print 1 (+ 2 3))

A TRAILING comma is allowed after the last argument, and changes nothing about the call.
Swift accepts `print(1,)` (SE-0439) and so do we — the argument loop stops when the token
after a comma is `)`:

  $ printf 'print(1,)\n' > g2.swift
  $ ./lab.exe --emit-expr g2.swift
  (print 1)
  $ printf 'print(1, 2,)\n' > g3.swift
  $ ./lab.exe --emit-expr g3.swift
  (print 1 2)

A LEADING comma is not: an argument list starts with an expression, so `print(,1)` is an
error, as it is for swiftc. (We report it twice where swiftc reports once — recovery, not
the verdict, and the oracle checks the verdict.)

  $ printf 'print(,1)\n' > g4.swift
  $ ./lab.exe --emit-expr g4.swift 2>&1 >/dev/null | head -1 | grep -c 'error:'
  1

A `*` where an operand should be is reported, exit 1.
Diagnostics go to stderr as `line:col: error: …`, exit 1. The wording is yours (§6
exercise 1 sharpens it), so only the shape is asserted:

  $ printf '*\n' > bad.swift
  $ ./lab.exe --emit-expr bad.swift 2>&1 >/dev/null | grep -c 'error:'
  1
  $ ./lab.exe --emit-expr bad.swift >/dev/null 2>&1; echo "exit=$?"
  exit=1
