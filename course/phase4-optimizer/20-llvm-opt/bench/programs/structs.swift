struct P { var x: Int; var y: Int }
func dot(_ a: P, _ b: P) -> Int { return a.x * b.x + a.y * b.y }
var acc = 0
for i in 0 ..< 20000000 {
  let p = P(x: i % 100, y: i % 37)
  let q = P(x: p.y, y: p.x)
  acc = acc + dot(p, q) % 1000
}
print(acc)
