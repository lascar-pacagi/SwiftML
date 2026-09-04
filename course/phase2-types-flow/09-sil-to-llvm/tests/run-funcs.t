Functions EXECUTED: the call ABI (arguments in, result out), recursion, and the two return
shapes. LLVM does the register allocation and the stack frame, so what these check is that each
`apply` became a `call` of the right type and each `return` a `ret` of the right type.

Arguments arrive in order, results come back, and calls nest.

  $ cat > a.swift <<'EOF'
  > func add(_ a: Int, _ b: Int) -> Int {
  >   return a + b
  > }
  > func sub(_ a: Int, _ b: Int) -> Int {
  >   return a - b
  > }
  > print(add(3, 4))
  > print(sub(3, 4))
  > print(add(add(1, 2), sub(10, 3)))
  > EOF
  $ ./lab.exe build a.swift -o a && ./a
  7
  -1
  10

Recursion works because nothing is shared: each call gets its own allocas.

  $ cat > f.swift <<'EOF'
  > func fib(_ n: Int) -> Int {
  >   if n < 2 { return n }
  >   return fib(n - 1) + fib(n - 2)
  > }
  > print(fib(10))
  > print(fib(20))
  > EOF
  $ ./lab.exe build f.swift -o f && ./f
  55
  6765

Mutual recursion works too — SILGen collected both signatures before lowering either body.

  $ cat > m.swift <<'EOF'
  > func isEven(_ n: Int) -> Bool {
  >   if n == 0 { return true }
  >   return isOdd(n - 1)
  > }
  > func isOdd(_ n: Int) -> Bool {
  >   if n == 0 { return false }
  >   return isEven(n - 1)
  > }
  > print(isEven(10))
  > print(isEven(7))
  > EOF
  $ ./lab.exe build m.swift -o m && ./m
  true
  false

A `Void` function returns `ret void`, and an early bare `return` leaves it.

  $ cat > v.swift <<'EOF'
  > func early(_ n: Int) {
  >   if n == 0 { return }
  >   print(n)
  > }
  > early(0)
  > early(7)
  > EOF
  $ ./lab.exe build v.swift -o v && ./v
  7

Loops inside functions: the counter's slot is local to the call, so `sum(0)` is 0 and `sum(10)`
is 45.

  $ cat > s.swift <<'EOF'
  > func sum(_ n: Int) -> Int {
  >   var s = 0
  >   for i in 0 ..< n { s = s + i }
  >   return s
  > }
  > print(sum(10))
  > print(sum(0))
  > print(sum(sum(4)))
  > EOF
  $ ./lab.exe build s.swift -o s && ./s
  45
  0
  15

Two real algorithms, as a smoke test for the whole phase.

  $ cat > g.swift <<'EOF'
  > func gcd(_ a: Int, _ b: Int) -> Int {
  >   var x = a
  >   var y = b
  >   while y != 0 {
  >     let t = y
  >     y = x % y
  >     x = t
  >   }
  >   return x
  > }
  > func collatz(_ start: Int) -> Int {
  >   var n = start
  >   var steps = 0
  >   while n != 1 {
  >     if n % 2 == 0 { n = n / 2 } else { n = 3 * n + 1 }
  >     steps = steps + 1
  >   }
  >   return steps
  > }
  > print(gcd(48, 18))
  > print(collatz(27))
  > EOF
  $ ./lab.exe build g.swift -o g && ./g
  6
  111
