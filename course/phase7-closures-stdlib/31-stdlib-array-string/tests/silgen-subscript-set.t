TODO(31b) — `a[i] = e`'s copy-on-write dance, in `silgen.ml`. The same three steps as
`append`, ending in `rt.array_set` instead of a push: load, make unique, store the pointer
back, write the element.

  $ cat > st.swift <<'SWIFT'
  > var a = [1, 2, 3]
  > a[1] = 99
  > print(a[0])
  > print(a[1])
  > print(a.count)
  > SWIFT
  $ ./lab.exe --emit-sil st.swift | grep -E 'rt.array_make_unique|rt.array_set'
    %16 = function_ref @rt.array_make_unique
    %19 = function_ref @rt.array_set
  $ ./lab.exe build st.swift -o st && ./st
  1
  99
  3

A shared buffer forks on the write, exactly as it does for `append` — this is the case that
fails silently if the unique pointer is not stored back into the slot:

  $ cat > cow.swift <<'SWIFT'
  > var a = [1, 2, 3]
  > let b = a
  > a[0] = 50
  > print(a[0])
  > print(b[0])
  > print(b.count)
  > SWIFT
  $ ./lab.exe build cow.swift -o cow && ./cow
  50
  1
  3

  $ ./lab.exe build cow.swift -O -o cowO && ./cowO
  50
  1
  3

A selection sort over `[3, 1, 2]` prints 1, 2, 3 — the writes land in the array being read,
which they would not if each one forked a fresh buffer and threw the previous one away:

  $ cat > sort.swift <<'SWIFT'
  > var a = [3, 1, 2]
  > var i = 0
  > while i < a.count {
  >   var j = i + 1
  >   while j < a.count {
  >     if a[j] < a[i] {
  >       let tmp = a[i]
  >       a[i] = a[j]
  >       a[j] = tmp
  >     }
  >     j = j + 1
  >   }
  >   i = i + 1
  > }
  > print(a[0])
  > print(a[1])
  > print(a[2])
  > SWIFT
  $ ./lab.exe build sort.swift -o sort && ./sort
  1
  2
  3

Writing past the end traps, with swiftc's message and swiftc's exit code — the bounds check
lives in the runtime, so the write path gets it for free:

  $ cat > oob.swift <<'SWIFT'
  > var a = [1, 2, 3]
  > a[5] = 0
  > SWIFT
  $ ./lab.exe build oob.swift -o oob
  $ sh -c './oob 2>msg.txt; echo exit=$?' 2>/dev/null
  exit=133
  $ cat msg.txt
  Fatal error: Index out of range

Three bindings, two forks: `c.append` forks c off the shared buffer, then `b[0] = 9` forks b
off what a still holds.

  $ cat > three.swift <<'SWIFT'
  > var a = [1, 2, 3]
  > var b = a
  > var c = b
  > c.append(4)
  > b[0] = 9
  > print(a[0])
  > print(a.count)
  > print(b[0])
  > print(b.count)
  > print(c[0])
  > print(c.count)
  > SWIFT
  $ ./lab.exe build three.swift -o three && ./three
  1
  3
  9
  3
  1
  4
