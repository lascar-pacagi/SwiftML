protocol Step { func next(_ x: Int) -> Int }
struct Inc: Step { var by: Int
  func next(_ x: Int) -> Int { return x + by } }
struct Mul: Step { var by: Int
  func next(_ x: Int) -> Int { return (x * by) % 99991 } }
func runChain(_ a: Step, _ b: Step, _ n: Int) -> Int {
  var x = 1
  for _i in 0 ..< n { x = b.next(a.next(x)) }
  return x
}
print(runChain(Inc(by: 7), Mul(by: 31), 10000000))
