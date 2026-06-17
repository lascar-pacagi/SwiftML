
// Sudoku solver — backtracking over a flat 81-cell [Int] board (0 = empty). Classic, hard.
func findEmpty(_ g: [Int]) -> Int {
  var i = 0
  while i < 81 { if g[i] == 0 { return i }; i = i + 1 }
  return -1
}
func valid(_ g: [Int], _ pos: Int, _ v: Int) -> Bool {
  let row = pos / 9
  let col = pos % 9
  var i = 0
  while i < 9 {
    if g[row * 9 + i] == v { return false }
    if g[i * 9 + col] == v { return false }
    i = i + 1
  }
  let br = (row / 3) * 3
  let bc = (col / 3) * 3
  var r = 0
  while r < 3 {
    var c = 0
    while c < 3 {
      if g[(br + r) * 9 + (bc + c)] == v { return false }
      c = c + 1
    }
    r = r + 1
  }
  return true
}
func solve(_ g: [Int]) -> [Int] {
  let pos = findEmpty(g)
  if pos == -1 { return g }
  var v = 1
  while v <= 9 {
    if valid(g, pos, v) {
      var ng = g
      ng[pos] = v
      let res = solve(ng)
      if res.count == 81 { return res }
    }
    v = v + 1
  }
  let fail: [Int] = []
  return fail
}
let puzzle = [5,3,0,0,7,0,0,0,0, 6,0,0,1,9,5,0,0,0, 0,9,8,0,0,0,0,6,0, 8,0,0,0,6,0,0,0,3, 4,0,0,8,0,3,0,0,1, 7,0,0,0,2,0,0,0,6, 0,6,0,0,0,0,2,8,0, 0,0,0,4,1,9,0,0,5, 0,0,0,0,8,0,0,7,9]
let sol = solve(puzzle)
print(sol.count)
var sum = 0
var i = 0
while i < sol.count { sum = sum + sol[i]; i = i + 1 }
print(sum)
var row0 = 0
var j = 0
while j < 9 { row0 = row0 * 10 + sol[j]; j = j + 1 }
print(row0)
