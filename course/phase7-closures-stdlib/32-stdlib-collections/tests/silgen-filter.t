TODO(32), the `filter` arm in `silgen.ml`'s `gen_array_hof`. The same counted walk as `map`,
with one difference that changes the shape of the body: the closure returns a `Bool`, so the
push is under a BRANCH.

`a.filter({ (x: Int) -> Bool in x % 2 == 0 })` keeps three of six, in order:

  $ cat > f.swift <<'SWIFT'
  > let a = [1, 2, 3, 4, 5, 6]
  > let evens = a.filter({ (x: Int) -> Bool in x % 2 == 0 })
  > print(evens.count)
  > for e in evens { print(e) }
  > SWIFT
  $ ./lab.exe build f.swift -o f && ./f
  3
  2
  4
  6

  $ ./lab.exe build f.swift -O -o fO && ./fO
  3
  2
  4
  6

The result's element type is the SOURCE's, not the closure's — a predicate returns `Bool`, and
`filter` still gives `[Int]`. That is the one place `filter` differs from `map` in typing as
well as in lowering:

  $ ./lab.exe --emit-sil f.swift | grep -c 'apply_value' || true
  1

A predicate that is never true gives an empty array; one that is always true gives a copy:

  $ cat > b.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > print(a.filter({ (x: Int) -> Bool in x > 100 }).count)
  > print(a.filter({ (x: Int) -> Bool in x > 0 }).count)
  > let empty: [Int] = []
  > print(empty.filter({ (x: Int) -> Bool in true }).count)
  > SWIFT
  $ ./lab.exe build b.swift -o b && ./b
  0
  3
  0

Chained with `map`, the two walks compose — filter first, then map over what survived:

  $ cat > c.swift <<'SWIFT'
  > let a = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  > let r = a.filter({ (x: Int) -> Bool in x % 2 == 1 }).map({ (x: Int) -> Int in x * x })
  > print(r.count)
  > for x in r { print(x) }
  > SWIFT
  $ ./lab.exe build c.swift -o c && ./c
  5
  1
  9
  25
  49
  81
