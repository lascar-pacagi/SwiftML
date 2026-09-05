Everything you can do to an array without mutating it, plus String (given code, so this file is
green from the start). Reads need no copy-on-write: nothing forks, so a literal, a `count`, a
subscript and a `for-in` are each one runtime call.

Array and String are lowered to runtime INTRINSICS — ordinary `apply`s of a `func_ref`. Not one
new SIL instruction was added for either type, which is the same trick concept 30 played with
the error register:

  $ cat > a.swift <<'SWIFT'
  > let a = [10, 20, 30]
  > print(a.count)
  > print(a[0] + a[2])
  > var sum = 0
  > for x in a { sum = sum + x }
  > print(sum)
  > let s = "hello"
  > print(s.count)
  > let t = s + " world"
  > print(t)
  > print(t.count)
  > SWIFT
  $ ./lab.exe --emit-sil a.swift | grep -o 'rt\.[a-z_]*' | sort -u
  rt.array_count
  rt.array_get
  rt.array_new
  rt.array_push
  rt.str_concat
  rt.str_count
  $ ./lab.exe build a.swift -o a && ./a
  3
  40
  60
  5
  hello world
  11

An empty literal needs its element type from the annotation, since there is nothing to infer it
from:

  $ cat > e.swift <<'SWIFT'
  > let empty: [Int] = []
  > print(empty.count)
  > print(empty.isEmpty)
  > let one = [7]
  > print(one.isEmpty)
  > SWIFT
  $ ./lab.exe build e.swift -o e && ./e
  0
  true
  false

A literal may span lines. A newline inside brackets separates nothing — there is no statement
there to separate — so the lexer drops `Newline` while the bracket depth is above zero. Without
that, this program was a parse error where swiftc accepts it, and the stress corpus had to
write its boards on one line.

  $ cat > ml.swift <<'SWIFT'
  > let a = [
  >   1,
  >   2,
  >   3
  > ]
  > print(a.count)
  > print(a[1])
  > SWIFT
  $ ./lab.exe build ml.swift -o ml && ./ml
  3
  2

Reading past the end traps with swiftc's message and swiftc's exit code. The bounds check is in
the runtime, so every subscript gets it:

  $ cat > oob.swift <<'SWIFT'
  > let a = [1, 2, 3]
  > print(a[5])
  > SWIFT
  $ ./lab.exe build oob.swift -o oob
  $ sh -c './oob 2>msg.txt; echo exit=$?' 2>/dev/null
  exit=133
  $ cat msg.txt
  Fatal error: Index out of range

An array is passed to a function by value — the pointer goes across, and the callee reads
through it:

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
