TODO(32), the `map` arm in `silgen.ml`'s `gen_array_hof`. One counted walk over the buffer,
calling the closure on each element and pushing the result into a fresh array. `map` is the
shape the other two are variations on, so it is the one to write first.

`a.map({ (x: Int) -> Int in x * 2 })` reads every element and builds a NEW array of the same
length — the source is untouched:

  $ cat > m.swift <<'SWIFT'
  > let a = [1, 2, 3, 4, 5, 6]
  > let doubled = a.map({ (x: Int) -> Int in x * 2 })
  > print(doubled.count)
  > print(doubled[0])
  > print(doubled[5])
  > print(a[0])
  > SWIFT
  $ ./lab.exe build m.swift -o m && ./m
  6
  2
  12
  1

  $ ./lab.exe build m.swift -O -o mO && ./mO
  6
  2
  12
  1

The closure is called through the thick-function pair, once per element — `apply_value` inside
a loop, which is precisely concept 29's indirect call meeting concept 31's buffer. No new SIL
instruction and no new runtime entry point were needed for any of the three:

  $ ./lab.exe --emit-sil m.swift | grep -c 'apply_value' || true
  1
  $ ./lab.exe --emit-sil m.swift | grep -o 'rt\.[a-z_]*' | sort -u
  rt.array_count
  rt.array_get
  rt.array_new
  rt.array_push

A closure that CAPTURES makes no difference to the loop — the captured value rides in the
context, and the walk cannot tell:

  $ cat > cap.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > let factor = 10
  > let scaled = a.map({ (x: Int) -> Int in x * factor })
  > print(scaled[0])
  > print(scaled[2])
  > SWIFT
  $ ./lab.exe build cap.swift -o cap && ./cap
  10
  30

Mapping an empty array runs the loop zero times and gives an empty array, not a crash:

  $ cat > e.swift <<'SWIFT'
  > let empty: [Int] = []
  > print(empty.map({ (x: Int) -> Int in x + 1 }).count)
  > SWIFT
  $ ./lab.exe build e.swift -o e && ./e
  0

The result is a fresh array with a fresh buffer, so appending to the SOURCE afterwards leaves
it alone:

  $ cat > fresh.swift <<'SWIFT'
  > var a = [1, 2, 3]
  > let b = a.map({ (x: Int) -> Int in x * 3 })
  > a.append(4)
  > print(a.count)
  > print(b.count)
  > print(b[2])
  > SWIFT
  $ ./lab.exe build fresh.swift -o fresh && ./fresh
  4
  3
  9
