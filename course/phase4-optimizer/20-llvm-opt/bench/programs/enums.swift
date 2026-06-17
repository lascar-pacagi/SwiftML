enum Op { case add(Int); case sub(Int); case reset }
func step(_ acc: Int, _ op: Op) -> Int {
  switch op {
  case .add(let v): return acc + v
  case .sub(let v): return acc - v
  case .reset: return 0
  }
}
var acc = 0
for i in 0 ..< 30000000 {
  let m = i % 3
  if m == 0 { acc = step(acc, Op.add(i % 7)) } else { if m == 1 { acc = step(acc, Op.sub(i % 5)) } else { acc = step(acc, Op.reset) } }
}
print(acc)
