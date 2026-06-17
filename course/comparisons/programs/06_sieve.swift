// Sieve of Eratosthenes: count primes below N and print a few.
func primeCount(_ n: Int) -> Int {
  var isComposite: [Int] = []
  var i = 0
  while i < n { isComposite.append(0); i = i + 1 }
  var count = 0
  var p = 2
  while p < n {
    if isComposite[p] == 0 {
      count = count + 1
      var m = p * p
      while m < n { isComposite[m] = 1; m = m + p }
    }
    p = p + 1
  }
  return count
}
print(primeCount(10))
print(primeCount(100))
print(primeCount(1000))
print(primeCount(10000))
