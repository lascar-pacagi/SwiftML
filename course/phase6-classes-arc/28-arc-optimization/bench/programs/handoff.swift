class Node {
  var v: Int
  init(_ v0: Int) { v = v0 }
  func get() -> Int { return v }
}
func pass3(_ n: Node) -> Int {
  let a = n
  let b = a
  let c = b
  return c.get()
}
func drive(_ n: Node, _ iters: Int) -> Int {
  var t = 0
  for i in 0 ..< iters {
    t = (t + pass3(n) + i) % 100003
  }
  return t
}
print(drive(Node(11), 20000000))
