// Phase 2 / concepts 07–09: several functions with different signatures calling one another.
// This keeps function declarations, argument order, return values, nested calls, and a Void
// call visible without the control-flow capstone's extra machinery.

func add(_ a: Int, _ b: Int) -> Int {
  return a + b
}

func twice(_ n: Int) -> Int {
  return add(n, n)
}

func choose(_ flag: Bool, _ yes: Int, _ no: Int) -> Int {
  if flag {
    return yes
  } else {
    return no
  }
}

func report(_ ok: Bool, _ value: Int) {
  print(ok)
  print(value)
}

print(twice(add(3, 4)))
print(choose(false, 10, 20))
report(true, add(2, 5))
