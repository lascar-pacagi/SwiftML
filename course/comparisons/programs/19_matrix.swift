// Matrix multiply with flat [Int] (row-major). 3x3 * 3x3.
func matmul(_ a: [Int], _ b: [Int], _ n: Int) -> [Int] {
  var c: [Int] = []
  var idx = 0
  while idx < n * n { c.append(0); idx = idx + 1 }
  var i = 0
  while i < n {
    var j = 0
    while j < n {
      var s = 0
      var k = 0
      while k < n { s = s + a[i * n + k] * b[k * n + j]; k = k + 1 }
      c[i * n + j] = s
      j = j + 1
    }
    i = i + 1
  }
  return c
}
let a = [1, 2, 3, 4, 5, 6, 7, 8, 9]
let b = [9, 8, 7, 6, 5, 4, 3, 2, 1]
let c = matmul(a, b, 3)
var t = 0
var k = 0
while k < c.count { t = t + c[k]; print(c[k]); k = k + 1 }
print(t)
