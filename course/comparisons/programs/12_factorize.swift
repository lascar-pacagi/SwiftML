// Prime factorization: return the factors as an [Int].
func factorize(_ input: Int) -> [Int] {
  var n = input
  var factors: [Int] = []
  var d = 2
  while d * d <= n {
    while n % d == 0 { factors.append(d); n = n / d }
    d = d + 1
  }
  if n > 1 { factors.append(n) }
  return factors
}
func show(_ n: Int) {
  let f = factorize(n)
  var k = 0
  var prod = 1
  while k < f.count { prod = prod * f[k]; k = k + 1 }
  print(f.count)
  print(prod)
}
show(360)
show(1024)
show(97)
show(123456)
