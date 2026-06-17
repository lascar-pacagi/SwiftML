
// A stack-based bytecode VM. Opcodes are an ENUM with a payload, DECODED on the fly from a parallel
// [Int] program (array-of-enum isn't in v0), then dispatched via SWITCH with payload binding.
enum Op {
  case push(Int)
  case binop(Int)   // 1=+ 2=- 3=* 4=/
  case dup
}
func decode(_ code: Int, _ arg: Int) -> Op {
  if code == 0 { return Op.push(arg) }
  if code == 2 { return Op.dup }
  return Op.binop(code)   // 1/3/4 etc.
}
func step(_ op: Op, _ stack: [Int]) -> [Int] {
  var s = stack
  switch op {
  case .push(let v): s.append(v)
  case .dup:
    let t = s[s.count - 1]
    s.append(t)
  case .binop(let k):
    let b = s[s.count - 1]
    let a = s[s.count - 2]
    var ns: [Int] = []
    var i = 0
    while i < s.count - 2 { ns.append(s[i]); i = i + 1 }
    var r = 0
    if k == 1 { r = a + b }
    if k == 3 { r = a * b }
    if k == 4 { r = a / b }
    ns.append(r)
    s = ns
  }
  return s
}
func run(_ code: [Int], _ arg: [Int]) -> Int {
  var stack: [Int] = []
  var pc = 0
  while pc < code.count {
    let op = decode(code[pc], arg[pc])
    stack = step(op, stack)
    pc = pc + 1
  }
  return stack[stack.count - 1]
}
// (2 dup *) (3 +)  => 2*2 + 3 = 7 ; then push 10, *  => 70
let code = [0, 2, 3, 0, 1, 0, 3]
let arg  = [2, 0, 0, 3, 0, 10, 0]
print(run(code, arg))
// 5 3 + 4 *  => 32
print(run([0,0,1,0,3], [5,3,0,4,0]))
