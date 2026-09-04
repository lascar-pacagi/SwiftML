The control flow concept 08 lowered, now EXECUTED. A CFG that verifies can still be wrong —
these cases are the ones that catch it, because a mis-aimed edge shows up as a wrong number or
a program that never stops.

`if`/`else` and an `else if` chain take exactly one arm.

  $ cat > i.swift <<'EOF'
  > let x = 5
  > if x < 0 { print(0) } else { print(1) }
  > let n = 2
  > if n == 1 { print(1) } else if n == 2 { print(2) } else { print(0) }
  > var m = 0
  > if m == 0 { m = m + 5 }
  > print(m)
  > EOF
  $ ./lab.exe build i.swift -o i && ./i
  1
  2
  5

A `while` runs its body until the condition fails, and `while false` never enters it.

  $ cat > w.swift <<'EOF'
  > var n = 0
  > while n < 5 { n = n + 1 }
  > print(n)
  > while false { print(1) }
  > print(0)
  > EOF
  $ ./lab.exe build w.swift -o w && ./w
  5
  0

A `for` runs `hi - lo` times, and an empty range never enters the body at all.

  $ cat > f.swift <<'EOF'
  > var s = 0
  > for i in 0 ..< 5 { s = s + i }
  > print(s)
  > for i in 0 ..< 3 { print(i) }
  > for i in 3 ..< 3 { print(99) }
  > EOF
  $ ./lab.exe build f.swift -o f && ./f
  10
  0
  1
  2

`break` leaves the loop at once — with a bound of 100 the program only terminates promptly if
the branch really goes to the exit block.

  $ cat > b.swift <<'EOF'
  > var n = 0
  > while n < 100 {
  >   n = n + 1
  >   if n > 3 { break }
  > }
  > print(n)
  > EOF
  $ ./lab.exe build b.swift -o b && ./b
  4

`continue` in a `for` must reach the LATCH, not the header — this program is the one that
caught the real bug: sending it to the header skipped `i = i + 1` and it looped forever.

  $ cat > c.swift <<'EOF'
  > var s = 0
  > for i in 0 ..< 5 {
  >   if i == 3 { continue }
  >   s = s + i
  > }
  > print(s)
  > EOF
  $ ./lab.exe build c.swift -o c && ./c
  7

Nested loops, with `break` and `continue` each addressing the inner one only.

  $ cat > n.swift <<'EOF'
  > var s = 0
  > for i in 0 ..< 4 {
  >   for j in 0 ..< 4 {
  >     if j == 2 { break }
  >     if i == 1 { continue }
  >     s = s + 1
  >   }
  > }
  > print(s)
  > var t = 0
  > var a = 0
  > while a < 4 {
  >   var d = 0
  >   while d < a {
  >     t = t + d
  >     d = d + 1
  >   }
  >   a = a + 1
  > }
  > print(t)
  > EOF
  $ ./lab.exe build n.swift -o n && ./n
  6
  4
