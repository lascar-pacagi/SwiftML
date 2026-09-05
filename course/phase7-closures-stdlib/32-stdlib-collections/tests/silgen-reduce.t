TODO(32), the `reduce` arm in `silgen.ml`'s `gen_array_hof`. The same counted walk again, but
the result is a SCALAR, not an array: an accumulator slot, seeded with the initial value and
overwritten each time round.

`a.reduce(0, { (s: Int, x: Int) -> Int in s + x })` folds left, so the accumulator is the
closure's FIRST argument and the element its second:

  $ cat > r.swift <<'SWIFT'
  > let a = [1, 2, 3, 4, 5, 6]
  > print(a.reduce(0, { (s: Int, x: Int) -> Int in s + x }))
  > print(a.reduce(1, { (s: Int, x: Int) -> Int in s * x }))
  > SWIFT
  $ ./lab.exe build r.swift -o r && ./r
  21
  720

  $ ./lab.exe build r.swift -O -o rO && ./rO
  21
  720

`reduce` builds NO result array — the only `rt.array_new` in this program is the literal's:

  $ cat > one.swift <<'SWIFT'
  > let a = [10, 20, 30]
  > print(a.reduce(0, { (s: Int, x: Int) -> Int in s + x }))
  > SWIFT
  $ ./lab.exe --emit-sil one.swift | grep -c 'rt.array_new' || true
  1
  $ ./lab.exe build one.swift -o one && ./one
  60

The accumulator is not restricted to a sum: a running maximum is the same fold with a different
closure, and an empty array returns the seed untouched:

  $ cat > mx.swift <<'SWIFT'
  > let a = [5, 3, 9, 1]
  > print(a.reduce(0, { (m: Int, x: Int) -> Int in m > x ? m : x }))
  > let empty: [Int] = []
  > print(empty.reduce(42, { (acc: Int, x: Int) -> Int in acc + x }))
  > SWIFT
  $ ./lab.exe build mx.swift -o mx && ./mx
  9
  42

Sum of squares in one pass, and the trio chained end to end — this is the program the whole
concept exists for:

  $ cat > sq.swift <<'SWIFT'
  > let a = [1, 2, 3, 4, 5]
  > print(a.reduce(0, { (acc: Int, x: Int) -> Int in acc + x * x }))
  > let odds = a.filter({ (x: Int) -> Bool in x % 2 == 1 })
  > let tens = odds.map({ (x: Int) -> Int in x * 10 })
  > print(tens.reduce(0, { (s: Int, x: Int) -> Int in s + x }))
  > SWIFT
  $ ./lab.exe build sq.swift -o sq && ./sq
  55
  90
