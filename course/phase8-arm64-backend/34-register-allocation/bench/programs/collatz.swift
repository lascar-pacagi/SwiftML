func collatz(_ start: Int) -> Int {
  var n = start
  var steps = 0
  while n != 1 { if n % 2 == 0 { n = n / 2 } else { n = 3 * n + 1 }
    steps = steps + 1 }
  return steps
}
var sum = 0
for i in 1 ..< 400000 { sum = sum + collatz(i) }
print(sum)
