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

`(_: Int)` is Swift's UNNAMED parameter — `_` is an ordinary identifier to the lexer, so it
lands in `pname` like any other name and the list is one parameter called `_`:

  $ printf '(_: Int)\n' > p5.swift
  $ ./lab.exe --emit-params p5.swift
  (_:Int)

All three label forms in one list — dropped `_`, a named label, none at all — read the same way:

  $ printf '(_ a: Int, from b: Bool, c: String)\n' > p6.swift
  $ ./lab.exe --emit-params p6.swift
  (a:Int b:Bool c:String)

The parser does not know what a type IS — it reads the written name and hands it to sema, so a
list of `Bool`, `String` and `Double` parses exactly like a list of `Int`:

  $ printf '(a: Bool, b: String, c: Double)\n' > p7.swift
  $ ./lab.exe --emit-params p7.swift
  (a:Bool b:String c:Double)

A list that does not open with `(` is "expected '('", at the token found there (only the first
diagnostic is pinned: the given `expect` does not skip, so what follows is recovery noise):

  $ printf 'x: Int)\n' > e1.swift
  $ ./lab.exe --emit-params e1.swift 2>&1 | head -1
  1:1: error: expected '('

`(a)` — one identifier, no type — has two defensible readings and this case takes EITHER: `a`
was the label, so the parameter NAME is missing; or `a` was the name, so the `:` is. Both
report at the `)`, and the `sed` folds the two wordings into one line. Swift reads it a third
way — see the explainer's §2:

  $ printf '(a)\n' > e2.swift
  $ ./lab.exe --emit-params e2.swift 2>&1 | head -1 | sed -E "s/(a parameter name|':')/a parameter name or ':'/"
  1:3: error: expected a parameter name or ':'

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

A list that opens with a comma — `(, _ a: Int)` — reports at the comma, where a name was due
(swiftc points at the same comma, calling it an "unexpected ',' separator"). Only the first
diagnostic is pinned; the parser then runs on:

  $ printf '(, _ a: Int)\n' > e6.swift
  $ ./lab.exe --emit-params e6.swift 2>&1 | head -1
  1:2: error: expected a parameter name

Two commas in a row — `(_ a: Int,, _ b: Int)` — report at the SECOND comma, the one standing
where a parameter should be (swiftc points there too):

  $ printf '(_ a: Int,, _ b: Int)\n' > e7.swift
  $ ./lab.exe --emit-params e7.swift 2>&1 | head -1
  1:11: error: expected a parameter name

Two parameters with no comma between them — `(_ a: Int _ b: Int)` — end the list at the second
`_`, so the error is "expected ')'" there, exactly once (swiftc points at the same token, and
says "expected ',' separator" — it knows a list continues, we only know it stopped):

  $ printf '(_ a: Int _ b: Int)\n' > e8.swift
  $ ./lab.exe --emit-params e8.swift; echo "exit=$?"
  1:11: error: expected ')'
  exit=1

A name and a type with no colon — `(a Int)` — is "expected ':'", at the `)`. This is the one
malformed list where our wording is swiftc's own: `expected_parameter_colon`, "expected ':'
following argument label and parameter name", reported at the same token:

  $ printf '(a Int)\n' > e9.swift
  $ ./lab.exe --emit-params e9.swift 2>&1 | head -1
  1:7: error: expected ':'

A list that hits end of input — `(_ a: Int` with no `)` — reports "expected ')'" at the end,
once. There is no token left to point at, so the span is the position after the last one:

  $ printf '(_ a: Int\n' > e10.swift
  $ ./lab.exe --emit-params e10.swift; echo "exit=$?"
  1:10: error: expected ')'
  exit=1

A keyword where a name goes — `(let a: Int)` — is rejected, and this is a DIVERGENCE we accept:
Swift allows most keywords as argument labels and merely warns ("'let' in this position is
interpreted as an argument label"), but our lexer turns `let` into `Kw_let`, which `parse_ident`
cannot take. Keyword labels are out of the v0 subset:

  $ printf '(let a: Int)\n' > e11.swift
  $ ./lab.exe --emit-params e11.swift 2>&1 | head -1
  1:2: error: expected a parameter name
