// Binary search tree as parallel index arrays (no optional class refs): insert + in-order.
func run() {
  var val: [Int] = []
  var left: [Int] = []
  var right: [Int] = []
  var root = -1
  let input = [5, 3, 8, 1, 4, 7, 9, 2, 6, 0]
  var k = 0
  while k < input.count {
    let x = input[k]
    if root == -1 {
      val.append(x); left.append(-1); right.append(-1); root = 0
    } else {
      var cur = root
      while true {
        if x < val[cur] {
          if left[cur] == -1 {
            val.append(x); left.append(-1); right.append(-1)
            left[cur] = val.count - 1
            cur = -1
          } else { cur = left[cur] }
        } else {
          if right[cur] == -1 {
            val.append(x); left.append(-1); right.append(-1)
            right[cur] = val.count - 1
            cur = -1
          } else { cur = right[cur] }
        }
        if cur == -1 { break }
      }
    }
    k = k + 1
  }
  // iterative in-order traversal using an explicit stack
  var stack: [Int] = []
  var cur = root
  while cur != -1 || stack.count > 0 {
    while cur != -1 { stack.append(cur); cur = left[cur] }
    cur = stack[stack.count - 1]
    var ns: [Int] = []
    var t = 0
    while t < stack.count - 1 { ns.append(stack[t]); t = t + 1 }
    stack = ns
    print(val[cur])
    cur = right[cur]
  }
}
run()
