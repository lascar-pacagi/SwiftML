// N-Queens: count solutions. Board passed by value (column of queen per row).
func safe(_ board: [Int], _ row: Int, _ col: Int) -> Bool {
  var r = 0
  while r < row {
    let c = board[r]
    if c == col { return false }
    if c - r == col - row { return false }
    if c + r == col + row { return false }
    r = r + 1
  }
  return true
}
func solve(_ board: [Int], _ row: Int, _ n: Int) -> Int {
  if row == n { return 1 }
  var total = 0
  var col = 0
  while col < n {
    if safe(board, row, col) {
      var next = board
      next.append(col)
      total = total + solve(next, row + 1, n)
    }
    col = col + 1
  }
  return total
}
var i = 1
while i <= 8 {
  let empty: [Int] = []
  print(solve(empty, 0, i))
  i = i + 1
}
