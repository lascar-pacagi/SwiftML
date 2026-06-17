Inlining replaces a call with the callee's body — and then folding/CSE/DCE run across the old
boundary. RED until the TODO(19) hole (the inline transform) is filled.

`sq(5)` is inlined into `main`, folded to `25`, and the now-uncalled `@sq` is removed:

  $ printf 'func sq(_ x: Int) -> Int { return x * x }\nprint(sq(5))\n' > q.swift
  $ ./lab.exe --emit-sil q.swift | grep -c '^sil @'
  2
  $ ./lab.exe --sil-opt q.swift | grep -c '^sil @'
  1
  $ ./lab.exe --sil-opt q.swift | grep -oE 'integer_literal \$Int, 25'
  integer_literal $Int, 25

`-O` preserves behavior — inlined leaves, nested calls, and inlining inside a loop:

  $ printf 'func sq(_ x: Int) -> Int { return x * x }\nprint(sq(5) + sq(6))\n' > a.swift
  $ ./lab.exe build a.swift -O -o a && ./a
  61

  $ cat > n.swift <<'EOF'
  > func add(_ a: Int, _ b: Int) -> Int { return a + b }
  > func mul(_ a: Int, _ b: Int) -> Int { return a * b }
  > print(add(mul(3, 4), mul(5, 6)))
  > EOF
  $ ./lab.exe build n.swift -O -o n && ./n
  42

A recursive function is NOT inlined (it would never terminate) — it still works:

  $ cat > f.swift <<'EOF'
  > func fib(_ n: Int) -> Int {
  >   if n < 2 { return n }
  >   return fib(n - 1) + fib(n - 2)
  > }
  > print(fib(20))
  > EOF
  $ ./lab.exe build f.swift -O -o f && ./f
  6765
