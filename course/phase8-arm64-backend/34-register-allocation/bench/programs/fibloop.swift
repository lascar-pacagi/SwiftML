func fib(_ n: Int) -> Int { if n < 2 { return n }
  return fib(n - 1) + fib(n - 2) }
var total = 0
for _k in 0 ..< 8 { total = total + fib(28) }
print(total)
