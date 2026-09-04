Parameter lists, through `--emit-ast`. Needs `parse_params` (and `parse_func` to reach it —
every case here is a `func` with an empty body, so only the list between the parentheses
varies). A parameter dumps as `name:Type`.

`()` is an empty list:

  $ printf 'func f() { }\n' > p0.swift
  $ ./lab.exe --emit-ast p0.swift
  (func f () ())

`(_ a: Int)` is one parameter named `a` — the `_` label is accepted and dropped:

  $ printf 'func f(_ a: Int) { }\n' > p1.swift
  $ ./lab.exe --emit-ast p1.swift
  (func f (a:Int) ())

`(_ a: Int, _ b: Bool, _ c: String)` keeps the three in order:

  $ printf 'func f(_ a: Int, _ b: Bool, _ c: String) { }\n' > p2.swift
  $ ./lab.exe --emit-ast p2.swift
  (func f (a:Int b:Bool c:String) ())

`(x: Int)` — no external label at all — is a parameter named `x`:

  $ printf 'func f(x: Int) { }\n' > p3.swift
  $ ./lab.exe --emit-ast p3.swift
  (func f (x:Int) ())

`(from start: Int)` — a named external label — keeps the inner name `start`:

  $ printf 'func f(from start: Int) { }\n' > p4.swift
  $ ./lab.exe --emit-ast p4.swift
  (func f (start:Int) ())

A missing `(` after the name is "expected '('", at the token found there (only the first
diagnostic is pinned: the given `expect` does not skip, so what follows is recovery noise):

  $ printf 'func f { }\n' > e1.swift
  $ ./lab.exe --emit-ast e1.swift 2>&1 | head -1
  1:8: error: expected '('

`(a)` — a name with no type — reads `a` as an external label whose name is missing, so the
first error is "expected a parameter name", at the `)`:

  $ printf 'func f(a) { }\n' > e2.swift
  $ ./lab.exe --emit-ast e2.swift 2>&1 | head -1
  1:9: error: expected a parameter name

A colon with nothing after it — `(a:)` — is "expected a parameter type":

  $ printf 'func f(a:) { }\n' > e3.swift
  $ ./lab.exe --emit-ast e3.swift; echo "exit=$?"
  1:10: error: expected a parameter type
  exit=1

A list that never closes — `(a: Int {` — is "expected ')'", at the `{`:

  $ printf 'func f(a: Int { }\n' > e4.swift
  $ ./lab.exe --emit-ast e4.swift; echo "exit=$?"
  1:15: error: expected ')'
  exit=1

A trailing comma — `(a: Int,)` — is "expected a parameter name", at the `)`:

  $ printf 'func f(a: Int,) { }\n' > e5.swift
  $ ./lab.exe --emit-ast e5.swift 2>&1 | head -1
  1:15: error: expected a parameter name
