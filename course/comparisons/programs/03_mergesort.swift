// Bottom-up (iterative) merge sort over [Int].
func mergesort(_ input: [Int]) -> [Int] {
  var a = input
  let n = a.count
  var width = 1
  while width < n {
    var lo = 0
    while lo < n {
      let mid = lo + width
      var hi = lo + 2 * width
      if hi > n { hi = n }
      if mid < hi {
        var merged: [Int] = []
        var i = lo
        var j = mid
        while i < mid && j < hi {
          if a[i] <= a[j] { merged.append(a[i]); i = i + 1 } else { merged.append(a[j]); j = j + 1 }
        }
        while i < mid { merged.append(a[i]); i = i + 1 }
        while j < hi { merged.append(a[j]); j = j + 1 }
        var t = 0
        while t < merged.count { a[lo + t] = merged[t]; t = t + 1 }
      }
      lo = lo + 2 * width
    }
    width = width * 2
  }
  return a
}
let r = mergesort([4, 1, 3, 9, 7, 0, 2, 8, 6, 5, 4, 1])
var k = 0
while k < r.count { print(r[k]); k = k + 1 }
