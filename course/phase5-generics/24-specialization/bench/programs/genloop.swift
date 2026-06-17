protocol Step { func next(_ x: Int) -> Int }
struct Mix: Step {
  var a: Int
  var b: Int
  func next(_ x: Int) -> Int { return (x * a + b) % 1000003 }
}
func iterate<T: Step>(_ s: T, _ x0: Int, _ n: Int) -> Int {
  var x = x0
  for _i in 0 ..< n { x = s.next(x) }
  return x
}
print(iterate(Mix(a: 31, b: 17), 1, 30000000))
