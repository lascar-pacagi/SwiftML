// Fibonacci three ways: iterative, naive recursive, and memoized (DP array).
func fibIter(_ n: Int) -> Int {
  if n < 2 { return n }
  var a = 0
  var b = 1
  var i = 2
  while i <= n { let c = a + b; a = b; b = c; i = i + 1 }
  return b
}
func fibRec(_ n: Int) -> Int {
  if n < 2 { return n }
  return fibRec(n - 1) + fibRec(n - 2)
}
func fibMemo(_ n: Int) -> Int {
  var memo: [Int] = []
  var i = 0
  while i <= n { memo.append(-1); i = i + 1 }
  memo[0] = 0
  if n >= 1 { memo[1] = 1 }
  var k = 2
  while k <= n { memo[k] = memo[k - 1] + memo[k - 2]; k = k + 1 }
  return memo[n]
}
print(fibIter(30))
print(fibRec(25))
print(fibMemo(40))
print(fibIter(40))
