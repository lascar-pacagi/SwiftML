// Towers of Hanoi: count the moves (2^n - 1) by actually recursing.
func hanoi(_ n: Int) -> Int {
  if n == 0 { return 0 }
  return hanoi(n - 1) + 1 + hanoi(n - 1)
}
var i = 1
while i <= 15 { print(hanoi(i)); i = i + 1 }
