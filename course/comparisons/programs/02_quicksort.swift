// Quicksort with an explicit work-stack (Lomuto partition), no recursion / no inout.
func quicksort(_ input: [Int]) -> [Int] {
  var a = input
  if a.count < 2 { return a }
  var loStack: [Int] = []
  var hiStack: [Int] = []
  loStack.append(0)
  hiStack.append(a.count - 1)
  while loStack.count > 0 {
    let hi = hiStack[hiStack.count - 1]
    let lo = loStack[loStack.count - 1]
    loStack[loStack.count - 1] = 0   // placeholder; we pop by tracking count
    var ls: [Int] = []
    var hs: [Int] = []
    var t = 0
    while t < loStack.count - 1 { ls.append(loStack[t]); hs.append(hiStack[t]); t = t + 1 }
    loStack = ls
    hiStack = hs
    if lo < hi {
      let pivot = a[hi]
      var i = lo - 1
      var j = lo
      while j < hi {
        if a[j] <= pivot {
          i = i + 1
          let tmp = a[i]; a[i] = a[j]; a[j] = tmp
        }
        j = j + 1
      }
      let tmp = a[i + 1]; a[i + 1] = a[hi]; a[hi] = tmp
      let p = i + 1
      loStack.append(lo); hiStack.append(p - 1)
      loStack.append(p + 1); hiStack.append(hi)
    }
  }
  return a
}
let r = quicksort([9, 3, 7, 1, 8, 2, 6, 5, 4, 0, 3, 9, 1])
var s = 0
var k = 0
while k < r.count { s = s * 10 + r[k]; k = k + 1 }
print(r[0])
print(r[r.count - 1])
print(s % 1000000)
