Parameter lists, through `--emit-params`, which parses ONE list and stops — so every case here
needs `parse_params` and nothing after it: `parse_func` may still be a TODO and this file can
go green. The source of each case IS the list, and a parameter dumps as `name:Type`, the same
text `--emit-ast` shows between the parentheses of a `func`.

`()` is an empty list:

  $ printf '()\n' > p0.swift
  $ ./lab.exe --emit-params p0.swift
  ()

`(_ a: Int)` is one parameter named `a` — the `_` label is accepted and dropped:

  $ printf '(_ a: Int)\n' > p1.swift
  $ ./lab.exe --emit-params p1.swift
  (a:Int)

`(_ a: Int, _ b: Bool, _ c: String)` keeps the three in order:

  $ printf '(_ a: Int, _ b: Bool, _ c: String)\n' > p2.swift
  $ ./lab.exe --emit-params p2.swift
  (a:Int b:Bool c:String)

`(x: Int)` — no external label at all — is a parameter named `x`:

  $ printf '(x: Int)\n' > p3.swift
  $ ./lab.exe --emit-params p3.swift
  (x:Int)

`(from start: Int)` — a named external label — keeps the inner name `start`:

  $ printf '(from start: Int)\n' > p4.swift
  $ ./lab.exe --emit-params p4.swift
  (start:Int)

A list that does not open with `(` is "expected '('", at the token found there (only the first
diagnostic is pinned: the given `expect` does not skip, so what follows is recovery noise):

  $ printf 'x: Int)\n' > e1.swift
  $ ./lab.exe --emit-params e1.swift 2>&1 | head -1
  1:1: error: expected '('

`(a)` — a name with no type — reads `a` as an external label whose name is missing, so the
first error is "expected a parameter name", at the `)`:

  $ printf '(a)\n' > e2.swift
  $ ./lab.exe --emit-params e2.swift 2>&1 | head -1
  1:3: error: expected a parameter name

A colon with nothing after it — `(a:)` — is "expected a parameter type", and the run exits 1:

  $ printf '(a:)\n' > e3.swift
  $ ./lab.exe --emit-params e3.swift; echo "exit=$?"
  1:4: error: expected a parameter type
  exit=1

A list that never closes — `(a: Int {` — is "expected ')'", at the `{`, and the run exits 1:

  $ printf '(a: Int {\n' > e4.swift
  $ ./lab.exe --emit-params e4.swift; echo "exit=$?"
  1:9: error: expected ')'
  exit=1

A trailing comma — `(a: Int,)` — is "expected a parameter name", at the `)`:

  $ printf '(a: Int,)\n' > e5.swift
  $ ./lab.exe --emit-params e5.swift 2>&1 | head -1
  1:9: error: expected a parameter name
