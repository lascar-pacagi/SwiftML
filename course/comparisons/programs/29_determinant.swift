
// Determinant of an NxN integer matrix via recursive Laplace (cofactor) expansion.
func minorOf(_ m: [Int], _ n: Int, _ skipRow: Int, _ skipCol: Int) -> [Int] {
  var out: [Int] = []
  var r = 0
  while r < n {
    if r != skipRow {
      var c = 0
      while c < n {
        if c != skipCol { out.append(m[r * n + c]) }
        c = c + 1
      }
    }
    r = r + 1
  }
  return out
}
func det(_ m: [Int], _ n: Int) -> Int {
  if n == 1 { return m[0] }
  if n == 2 { return m[0] * m[3] - m[1] * m[2] }
  var total = 0
  var sign = 1
  var c = 0
  while c < n {
    let sub = minorOf(m, n, 0, c)
    total = total + sign * m[c] * det(sub, n - 1)
    sign = 0 - sign
    c = c + 1
  }
  return total
}
print(det([1,2,3, 4,5,6, 7,8,10], 3))     // 3x3 => -3
print(det([2,0,0,0, 0,3,0,0, 0,0,4,0, 0,0,0,5], 4))  // diagonal => 120
print(det([6,1,1, 4,-2,5, 2,8,7], 3))     // => -306
