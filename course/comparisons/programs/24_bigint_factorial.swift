
// Arbitrary-precision factorial via array-of-digits (little-endian) multiplication + CoW + grow.
func factorial(_ n: Int) -> [Int] {
  var digits: [Int] = []
  digits.append(1)
  var k = 2
  while k <= n {
    var carry = 0
    var i = 0
    while i < digits.count {
      let prod = digits[i] * k + carry
      digits[i] = prod % 10
      carry = prod / 10
      i = i + 1
    }
    while carry > 0 { digits.append(carry % 10); carry = carry / 10 }
    k = k + 1
  }
  return digits
}
let f = factorial(50)
print(f.count)
var sum = 0
var i = 0
while i < f.count { sum = sum + f[i]; i = i + 1 }
print(sum)
// most-significant 6 digits (little-endian, so read from the top)
var top = 0
var j = f.count - 1
var taken = 0
while j >= 0 && taken < 6 { top = top * 10 + f[j]; j = j - 1; taken = taken + 1 }
print(top)
