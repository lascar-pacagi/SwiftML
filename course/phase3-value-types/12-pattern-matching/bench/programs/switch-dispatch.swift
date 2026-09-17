enum Op {
  case add, sub, mul, divi, modu, mini, maxi, neg
}

func next(_ op: Op) -> Op {
  switch op {
  case .add: return Op.sub
  case .sub: return Op.mul
  case .mul: return Op.divi
  case .divi: return Op.modu
  case .modu: return Op.mini
  case .mini: return Op.maxi
  case .maxi: return Op.neg
  case .neg: return Op.add
  }
}

func apply(_ op: Op, _ a: Int, _ b: Int) -> Int {
  switch op {
  case .add: return a + b
  case .sub: return a - b
  case .mul: return a * b
  case .divi: return a / b
  case .modu: return a % b
  case .mini:
    if a < b { return a }
    return b
  case .maxi:
    if a > b { return a }
    return b
  case .neg: return 0 - a
  }
}

var op = Op.add
var acc = 0
for i in 0 ..< 20000000 {
  op = next(op)
  acc = acc + apply(op, i % 97 + 1, i % 13 + 1)
}
print(acc)
