// Iterative binary search; report found indices (or -1).
func bsearch(_ a: [Int], _ target: Int) -> Int {
  var lo = 0
  var hi = a.count - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    if a[mid] == target { return mid }
    if a[mid] < target { lo = mid + 1 } else { hi = mid - 1 }
  }
  return -1
}
let a = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]
print(bsearch(a, 7))
print(bsearch(a, 1))
print(bsearch(a, 19))
print(bsearch(a, 8))
print(bsearch(a, 100))
