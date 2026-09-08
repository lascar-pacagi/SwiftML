// Phase 2 / concept 08: `&&` and `||` are CONTROL FLOW, not arithmetic.
//
// They are the one expression that builds blocks. `a && b` lowers to the same diamond as an
// `if`: evaluate `a`, and only on the deciding edge evaluate `b`, merging the two answers
// through a stack slot. Read the SIL and you will find a cond_br inside an expression.
//
// Lowering them as a bitwise `and` would be a real bug, not an inefficiency: the right
// operand would run even when the left already decided the answer.

func loud(_ x: Int) -> Int {
  print(x)                // prints only if it is actually evaluated
  return x
}

// the right operand is NOT evaluated: false && _ is already false, so `loud(1)` never runs
if false && loud(1) > 0 {
  print(100)
}

// nor here: true || _ is already true
if true || loud(2) > 0 {
  print(3)                // 3
}

// and here it IS evaluated, because the left operand did not decide
if true && loud(4) > 0 {
  print(5)                // 4 then 5
}

// the result of `&&` is a value like any other — it can be bound, so the slot the two
// answers merge through becomes an ordinary variable's slot
let both = loud(6) > 0 && loud(7) > 0
print(both)               // 6, 7, true

// chained, the diamonds nest: each `&&` is its own merge
let a = 1
let b = 2
let c = 3
print(a < b && b < c && a < c)   // true
