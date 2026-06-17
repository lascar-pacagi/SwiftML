func isPrime(_ n: Int) -> Bool {
  if n < 2 { return false }
  var d = 2
  while d * d <= n {
    if n % d == 0 { return false }
    d = d + 1
  }
  return true
}
var count = 0
for n in 0 ..< 3000000 {
  if isPrime(n) { count = count + 1 }
}
print(count)
