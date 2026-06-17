var total = 0
for start in 1 ..< 1000000 {
  var n = start
  while n != 1 {
    if n % 2 == 0 { n = n / 2 } else { n = 3 * n + 1 }
    total = total + 1
  }
}
print(total)
