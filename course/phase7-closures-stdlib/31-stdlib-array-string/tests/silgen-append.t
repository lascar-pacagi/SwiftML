TODO(31a) — `append`'s copy-on-write dance, in `silgen.ml`. An array is a pointer to a
refcounted buffer, so two bindings can point at the same one; a mutation through either must
not be visible through the other. The rule is: before you write, make the buffer unique.

`a.append(3)` on `var a = [1, 2]` shows the dance: `rt.array_make_unique` (which copies iff
the refcount is above one, and returns the pointer to write through) between the load and the
push. Store that pointer BACK into the slot, or the copy is made, written to, and dropped on
the floor. The first two pushes below build the literal; the third is the append.

  $ cat > ap.swift <<'SWIFT'
  > var a = [1, 2]
  > a.append(3)
  > print(a.count)
  > print(a[2])
  > SWIFT
  $ ./lab.exe --emit-sil ap.swift | grep -E 'rt.array_make_unique|rt.array_push'
    %4 = function_ref @rt.array_push
    %6 = function_ref @rt.array_push
    %12 = function_ref @rt.array_make_unique
    %15 = function_ref @rt.array_push
  $ ./lab.exe build ap.swift -o ap && ./ap
  3
  3

Value semantics, the point of the whole exercise: `var b = a` shares the buffer, and appending
to `b` copies it, leaving `a` at its old length:

  $ cat > cow.swift <<'SWIFT'
  > var a = [1, 2, 3]
  > var b = a
  > b.append(4)
  > print(a.count)
  > print(b.count)
  > print(a[0] + b[0])
  > SWIFT
  $ ./lab.exe build cow.swift -o cow && ./cow
  3
  4
  2

  $ ./lab.exe build cow.swift -O -o cowO && ./cowO
  3
  4
  2

Sharing is what makes the copy necessary, and it is one retain: `var b = a` retains, a fresh
literal does not.

  $ ./lab.exe --emit-sil cow.swift | grep -c 'rt.array_retain' || true
  1

Twenty appends to an array nobody else holds still give the right length and the right last
element — `make_unique` hands back the same pointer every time, so the loop grows one buffer
rather than twenty:

  $ cat > loop.swift <<'SWIFT'
  > var a: [Int] = []
  > var i = 0
  > while i < 20 {
  >   a.append(i * i)
  >   i = i + 1
  > }
  > print(a.count)
  > print(a[19])
  > SWIFT
  $ ./lab.exe build loop.swift -o loop && ./loop
  20
  361

Passing an array to a function passes the pointer; the callee's own `var` copy is where the
buffer forks, so the caller's array is untouched:

  $ cat > fn.swift <<'SWIFT'
  > func grow(_ a: [Int]) -> Int {
  >   var c = a
  >   c.append(999)
  >   return c.count
  > }
  > var xs = [1, 2]
  > print(grow(xs))
  > print(xs.count)
  > SWIFT
  $ ./lab.exe build fn.swift -o fn && ./fn
  3
  2
