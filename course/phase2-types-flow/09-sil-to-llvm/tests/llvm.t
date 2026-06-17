End-to-end: compile Phase-2 programs with ./lab.exe and RUN them — the first time since Phase 1
that programs execute. Self-contained (no swiftc needed); every expected value also matches
swiftc. Plus FileCheck on the LLVM IR shape. RED until IRGen's TODO(09) holes are filled.

LLVM IR shape — a function lowers to memory-based IR (alloca/load/store), arithmetic is typed:

  $ printf 'func sq(_ x: Int) -> Int {\n  return x * x\n}\nprint(sq(6))\n' > q.swift
  $ ./lab.exe --emit-llvm q.swift | grep -c "define i64 @sq"
  1
  $ ./lab.exe --emit-llvm q.swift | grep -oE "mul i64" | head -1
  mul i64

Arithmetic + an if/else, compiled and run:

  $ cat > a.swift <<'EOF'
  > print(1 + 2 * 3 - 10 / 2)
  > let x = 5
  > if x < 0 { print(0) } else { print(1) }
  > EOF
  $ ./lab.exe build a.swift -o a && ./a
  2
  1

A recursive function runs:

  $ cat > fib.swift <<'EOF'
  > func fib(_ n: Int) -> Int {
  >   if n < 2 { return n }
  >   return fib(n - 1) + fib(n - 2)
  > }
  > print(fib(10))
  > EOF
  $ ./lab.exe build fib.swift -o fib && ./fib
  55

A `for` loop with `continue` runs (and terminates — the increment is in the loop's latch):

  $ cat > loop.swift <<'EOF'
  > var s = 0
  > for i in 0 ..< 5 {
  >   if i == 3 { continue }
  >   s = s + i
  > }
  > print(s)
  > EOF
  $ ./lab.exe build loop.swift -o loop && ./loop
  7
