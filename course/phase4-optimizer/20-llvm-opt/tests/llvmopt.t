Concept 20: `-O` = our SIL passes + LLVM's optimizer (clang -O2). RED until the TODO(20) hole
(wiring -O through to clang) is filled — `-Onone` builds work either way.

`-Onone` works even on the skeleton; `-O` needs the TODO:

  $ printf 'func sq(_ x: Int) -> Int { return x * x }\nprint(sq(5) + sq(6))\n' > q.swift
  $ ./lab.exe build q.swift -o q0 && ./q0
  61
  $ ./lab.exe build q.swift -O -o qO && ./qO
  61

A `let` inside a hot loop must not grow the stack (the alloca-in-loop bug this concept's
benchmark caught — every alloca is hoisted to the entry block):

  $ cat > hot.swift <<'EOF'
  > struct P { var x: Int; var y: Int }
  > var acc = 0
  > for i in 0 ..< 3000000 {
  >   let p = P(x: i % 100, y: i % 37)
  >   acc = acc + p.x + p.y
  > }
  > print(acc)
  > EOF
  $ ./lab.exe build hot.swift -o hot0 && ./hot0
  202499949
  $ ./lab.exe build hot.swift -O -o hotO && ./hotO
  202499949

The whole Phase-4 pipeline, end to end — inline + SSA + fold + GVN, then LLVM:

  $ cat > all.swift <<'EOF'
  > func dot(_ ax: Int, _ ay: Int, _ bx: Int, _ by: Int) -> Int { return ax * bx + ay * by }
  > var s = 0
  > for i in 1 ..< 1000 {
  >   if dot(i, i, i, i) % 2 == 0 { s = s + dot(i, 1, 1, i) }
  > }
  > print(s)
  > EOF
  $ ./lab.exe build all.swift -O -o all && ./all
  999000
