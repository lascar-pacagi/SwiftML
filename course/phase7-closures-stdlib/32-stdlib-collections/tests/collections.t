map / filter / reduce over Array<Int> — closures (29) meet containers (31). The payoff of M7.
RED until the TODO(32) hole (lowering the three higher-order functions over the buffer).

The trio, chained, with a captured variable — matches swiftc byte-for-byte, at -Onone and -O:

  $ cat > a.swift <<'SWIFT'
  > let a = [1, 2, 3, 4, 5, 6]
  > let doubled = a.map({ (x: Int) -> Int in x * 2 })
  > print(doubled[5])
  > print(doubled.reduce(0, { (s: Int, x: Int) -> Int in s + x }))
  > let evens = a.filter({ (x: Int) -> Bool in x % 2 == 0 })
  > print(evens.count)
  > for e in evens { print(e) }
  > let factor = 10
  > let scaled = a.map({ (x: Int) -> Int in x * factor })
  > print(scaled[5])
  > let sumSq = a.reduce(0, { (acc: Int, x: Int) -> Int in acc + x * x })
  > print(sumSq)
  > SWIFT
  $ ./lab.exe build a.swift -o a && ./a
  12
  42
  3
  2
  4
  6
  60
  91
  $ ./lab.exe build a.swift -O -o aO && ./aO
  12
  42
  3
  2
  4
  6
  60
  91

filter that keeps nothing, and the trio on an empty array — boundary cases match swiftc:

  $ cat > e.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > print(a.filter({ (x: Int) -> Bool in x > 100 }).count)
  > let empty: [Int] = []
  > print(empty.map({ (x: Int) -> Int in x + 1 }).count)
  > print(empty.reduce(42, { (acc: Int, x: Int) -> Int in acc + x }))
  > SWIFT
  $ ./lab.exe build e.swift -o e && ./e
  0
  0
  42

The lowering: each is a counted loop calling the closure per element via `apply_value` — no new
SIL, no new runtime (reuses the concept-31 buffer intrinsics + concept-29 closures):

  $ ./lab.exe --emit-sil a.swift | grep -c 'apply_value' || true
  5
  $ ./lab.exe --emit-sil a.swift | grep -o 'rt.array_get\|rt.array_push\|rt.array_count\|rt.array_new' | sort -u
  rt.array_count
  rt.array_get
  rt.array_new
  rt.array_push

reduce produces a scalar (no result array); map/filter each build one fresh result array:

  $ cat > r.swift <<'SWIFT'
  > let a = [10, 20, 30]
  > print(a.reduce(0, { (s: Int, x: Int) -> Int in s + x }))
  > SWIFT
  $ ./lab.exe --emit-sil r.swift | grep -c 'rt.array_new' || true
  1
  $ ./lab.exe build r.swift -o r && ./r
  60

A closure whose element/return types don't match the array is rejected, like swiftc:

  $ cat > bad.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > let b = a.filter({ (x: Int) -> Int in x * 2 })
  > print(b.count)
  > SWIFT
  $ ./lab.exe --typecheck bad.swift
  2:9: error: filter expects a closure '(Int) -> Bool', found '(Int) -> Int'
  [1]
