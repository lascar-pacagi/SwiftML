The typing rules for `map`, `filter` and `reduce` (given code, so this file is green from the
start). Each has a closure of a fixed shape, and the shape is what determines the result type.

`map`'s closure may return anything; the result is an array of THAT. A closure that takes the
wrong element type is refused:

  $ cat > mp.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > let b = a.map({ (s: Bool) -> Int in 1 })
  > SWIFT
  $ ./lab.exe --typecheck mp.swift
  2:9: error: map expects a closure '(Int) -> R', found '(Bool) -> Int'
  [1]

`filter`'s closure must return `Bool` — it is a PREDICATE, and a closure returning `Int` is a
different function even though the loop would run:

  $ cat > fl.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > let b = a.filter({ (x: Int) -> Int in x * 2 })
  > SWIFT
  $ ./lab.exe --typecheck fl.swift
  2:9: error: filter expects a closure '(Int) -> Bool', found '(Int) -> Int'
  [1]

`reduce`'s closure takes the accumulator FIRST and the element second, and must return the
accumulator's type — three constraints, and the message names all three:

  $ cat > rd.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > let b = a.reduce(0, { (s: Int, x: Int) -> Bool in true })
  > SWIFT
  $ ./lab.exe --typecheck rd.swift
  2:9: error: reduce expects '(Int, Int) -> Int', found '(Int, Int) -> Bool'
  [1]

`reduce` takes two arguments. Called with one, it used to be reported as a missing member,
which then cascaded into a complaint about printing `()`:

  $ cat > ar.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > let b = a.reduce(0)
  > SWIFT
  $ ./lab.exe --typecheck ar.swift
  2:9: error: method 'reduce' expects 2 argument(s) but 1 given
  [1]

The argument has to be a function at all:

  $ cat > nf.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > let b = a.map(5)
  > SWIFT
  $ ./lab.exe --typecheck nf.swift
  2:9: error: map expects a closure '(Int) -> R', found 'Int'
  [1]

`filter` gives back the SOURCE's element type, not the predicate's `Bool` — so a chained
pipeline type-checks, and a `[Bool]` never appears:

  $ cat > ch.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > let n = a.filter({ (x: Int) -> Bool in x > 1 }).map({ (x: Int) -> Int in x + 1 }).count
  > print(n)
  > SWIFT
  $ ./lab.exe --typecheck ch.swift

A `map` whose closure returns `Bool` would need a `[Bool]`, which concept 31's buffer cannot
hold — so the v0 scope refuses it here rather than at the store:

  $ cat > mb.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > let b: [Int] = a.map({ (x: Int) -> Bool in x > 1 })
  > SWIFT
  $ ./lab.exe --typecheck mb.swift
  2:16: error: arrays of 'Bool' are not supported in this subset (only '[Int]'; element-generic buffers are this concept's exercise)
  2:16: error: cannot convert value of type '[Bool]' to specified type '[Int]'
  [1]

An unknown member is still an unknown member:

  $ cat > nm.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > print(a.fold(0, { (s: Int, x: Int) -> Int in s + x }))
  > SWIFT
  $ ./lab.exe --typecheck nm.swift
  2:7: error: value of type '[Int]' has no member 'fold'
  2:7: error: cannot print a value of type '()' (only Int, Double, Bool and String)
  [1]
