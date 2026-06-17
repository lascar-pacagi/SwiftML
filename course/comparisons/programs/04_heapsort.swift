// Heapsort (build max-heap, sift down) over [Int].
func heapsort(_ input: [Int]) -> [Int] {
  var a = input
  let n = a.count
  // build heap
  var start = n / 2 - 1
  while start >= 0 {
    var root = start
    while root * 2 + 1 < n {
      var child = root * 2 + 1
      if child + 1 < n && a[child] < a[child + 1] { child = child + 1 }
      if a[root] < a[child] {
        let t = a[root]; a[root] = a[child]; a[child] = t
        root = child
      } else { root = n }
    }
    start = start - 1
  }
  // sort
  var end = n - 1
  while end > 0 {
    let t = a[0]; a[0] = a[end]; a[end] = t
    var root = 0
    while root * 2 + 1 < end {
      var child = root * 2 + 1
      if child + 1 < end && a[child] < a[child + 1] { child = child + 1 }
      if a[root] < a[child] {
        let t2 = a[root]; a[root] = a[child]; a[child] = t2
        root = child
      } else { root = end }
    }
    end = end - 1
  }
  return a
}
let r = heapsort([7, 2, 9, 4, 1, 8, 3, 6, 0, 5])
var k = 0
while k < r.count { print(r[k]); k = k + 1 }
