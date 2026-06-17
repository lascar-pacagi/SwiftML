
// Kruskal's Minimum Spanning Tree with union-find (path compression) over edge arrays.
func find(_ parent: [Int], _ x: Int) -> Int {
  var p = parent
  var r = x
  while p[r] != r { r = p[r] }
  return r
}
func kruskal(_ u: [Int], _ v: [Int], _ w: [Int], _ n: Int) -> Int {
  let m = u.count
  // sort edges by weight (selection sort on parallel arrays)
  var su = u
  var sv = v
  var sw = w
  var i = 0
  while i < m {
    var min = i
    var j = i + 1
    while j < m {
      if sw[j] < sw[min] { min = j }
      j = j + 1
    }
    let tw = sw[i]; sw[i] = sw[min]; sw[min] = tw
    let tu = su[i]; su[i] = su[min]; su[min] = tu
    let tv = sv[i]; sv[i] = sv[min]; sv[min] = tv
    i = i + 1
  }
  var parent: [Int] = []
  var k = 0
  while k < n { parent.append(k); k = k + 1 }
  var total = 0
  var edges = 0
  i = 0
  while i < m && edges < n - 1 {
    let ru = find(parent, su[i])
    let rv = find(parent, sv[i])
    if ru != rv {
      parent[ru] = rv
      total = total + sw[i]
      edges = edges + 1
    }
    i = i + 1
  }
  return total
}
// 4 vertices, edges (0-1:10)(0-2:6)(0-3:5)(1-3:15)(2-3:4) => MST weight 19
print(kruskal([0,0,0,1,2], [1,2,3,3,3], [10,6,5,15,4], 4))
