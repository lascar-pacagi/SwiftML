class Acc {
  var n: Int
  init(_ n0: Int) { n = n0 }
  func add(_ x: Int) -> Int { return n + x }
}
func run(_ a: Acc, _ iters: Int) -> Int {
  var total = 0
  for i in 0 ..< iters {
    let c = a
    total = total + c.add(i) % 1000
  }
  return total
}
print(run(Acc(7), 30000000))
