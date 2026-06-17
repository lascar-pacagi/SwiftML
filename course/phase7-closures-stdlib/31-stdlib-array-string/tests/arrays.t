Array<Int> on a refcounted heap buffer with copy-on-write value semantics, plus String.
RED until the TODO(31) holes (the append + subscript-set copy-on-write dances).

A full array program — literal, count, subscript read/write, append, for-in, String — matches
swiftc byte-for-byte, at -Onone and -O:

  $ cat > a.swift <<'SWIFT'
  > var a = [10, 20, 30]
  > print(a.count)
  > print(a[0] + a[2])
  > a.append(40)
  > a[1] = 99
  > print(a.count)
  > print(a[1])
  > var sum = 0
  > for x in a { sum = sum + x }
  > print(sum)
  > let empty: [Int] = []
  > print(empty.count)
  > print(empty.isEmpty)
  > var s = "hello"
  > print(s.count)
  > let t = s + " world"
  > print(t)
  > print(t.count)
  > SWIFT
  $ ./lab.exe build a.swift -o a && ./a
  3
  40
  4
  99
  179
  0
  true
  5
  hello world
  11
  $ ./lab.exe build a.swift -O -o aO && ./aO
  3
  40
  4
  99
  179
  0
  true
  5
  hello world
  11

Copy-on-write VALUE semantics: `var b = a` shares the buffer; mutating `b` copies it, leaving
`a` untouched — exactly swiftc's behavior:

  $ cat > cow.swift <<'SWIFT'
  > var a = [1, 2, 3]
  > a.append(4)
  > var b = a
  > b.append(5)
  > b[0] = 99
  > print(a.count)
  > print(a[0])
  > print(b.count)
  > print(b[0])
  > SWIFT
  $ ./lab.exe build cow.swift -o cow && ./cow
  4
  1
  5
  99

The SIL shows the desugaring — Array/String are runtime intrinsics (`rt.array_*` / `rt.str_*`),
no new SIL instructions; the make_unique call is the copy-on-write check:

  $ ./lab.exe --emit-sil cow.swift | grep -c 'rt.array_make_unique' || true
  3
  $ ./lab.exe --emit-sil a.swift | grep -o 'rt.array_new\|rt.array_push\|rt.array_get\|rt.array_count\|rt.str_concat\|rt.str_count' | sort -u
  rt.array_count
  rt.array_get
  rt.array_new
  rt.array_push
  rt.str_concat
  rt.str_count

`var b = a` retains the shared buffer (the CoW sharing); a fresh literal does not:

  $ ./lab.exe --emit-sil cow.swift | grep -c 'rt.array_retain' || true
  1

Out-of-bounds subscript traps like swiftc — the "Index out of range" message and exit 133:

  $ cat > oob.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > print(a[5])
  > SWIFT
  $ ./lab.exe build oob.swift -o oob
  $ sh -c './oob 2>msg.txt; echo exit=$?' 2>/dev/null
  exit=133
  $ cat msg.txt
  Fatal error: Index out of range

Arrays pass to functions by value and iterate with for-in:

  $ cat > fn.swift <<'SWIFT'
  > func total(_ a: [Int]) -> Int {
  >   var s = 0
  >   for x in a { s = s + x }
  >   return s
  > }
  > print(total([100, 20, 3]))
  > SWIFT
  $ ./lab.exe build fn.swift -o fn && ./fn
  123

`[String]` is rejected up front (v0's buffer is a homogeneous i64 store — only `[Int]`):

  $ cat > bad.swift <<'SWIFT'
  > let names = ["a", "b"]
  > print(names.count)
  > SWIFT
  $ ./lab.exe --typecheck bad.swift
  1:13: error: arrays of 'String' are not supported in this subset (only '[Int]'; element-generic buffers are this concept's exercise)
  [1]
