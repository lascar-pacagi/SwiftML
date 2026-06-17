// RPN (postfix) calculator with an [Int] value stack.
// The program is two parallel [Int] arrays: kind[] (0 = push number, 1 = +, 2 = -, 3 = *) and
// num[] (the operand when kind == 0). ([Int]-only — concept 31's v0 has no array of enum.)
func evalRPN(_ kind: [Int], _ num: [Int]) -> Int {
  var stack: [Int] = []
  var i = 0
  while i < kind.count {
    if kind[i] == 0 {
      stack.append(num[i])
    } else {
      let b = stack[stack.count - 1]
      let a = stack[stack.count - 2]
      var r = 0
      if kind[i] == 1 { r = a + b }
      if kind[i] == 2 { r = a - b }
      if kind[i] == 3 { r = a * b }
      // pop two, push one: shrink by rebuilding (no removeLast in v0)
      var ns: [Int] = []
      var t = 0
      while t < stack.count - 2 { ns.append(stack[t]); t = t + 1 }
      ns.append(r)
      stack = ns
    }
    i = i + 1
  }
  return stack[stack.count - 1]
}
// (3 4 +) (5 *) => 35
print(evalRPN([0, 0, 1, 0, 3], [3, 4, 0, 5, 0]))
// (10 2 -) (3 *) => 24
print(evalRPN([0, 0, 2, 0, 3], [10, 2, 0, 3, 0]))
// 2 (3 4 *) + => 14
print(evalRPN([0, 0, 0, 3, 1], [2, 3, 4, 0, 0]))
