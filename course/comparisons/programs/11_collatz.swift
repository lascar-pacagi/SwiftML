// Longest Collatz chain for starts below N.
func chainLength(_ start: Int) -> Int {
  var n = start
  var steps = 0
  while n != 1 {
    if n % 2 == 0 { n = n / 2 } else { n = 3 * n + 1 }
    steps = steps + 1
  }
  return steps
}
func longestUnder(_ limit: Int) -> Int {
  var best = 0
  var bestStart = 1
  var i = 1
  while i < limit {
    let l = chainLength(i)
    if l > best { best = l; bestStart = i }
    i = i + 1
  }
  return bestStart
}
print(chainLength(27))
print(longestUnder(1000))
print(longestUnder(10000))
