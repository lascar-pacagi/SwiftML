// Insertion sort over [Int] (iterative, value-semantic copy).
func sorted(_ input: [Int]) -> [Int] {
  var a = input
  var i = 1
  while i < a.count {
    let key = a[i]
    var j = i - 1
    while j >= 0 && a[j] > key {
      a[j + 1] = a[j]
      j = j - 1
    }
    a[j + 1] = key
    i = i + 1
  }
  return a
}
let r = sorted([5, 2, 8, 1, 9, 3, 7, 4, 6, 0, 5, 2])
var k = 0
while k < r.count { print(r[k]); k = k + 1 }
