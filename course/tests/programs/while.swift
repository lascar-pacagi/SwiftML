// Phase 2 / concept 08: the `while` LOOP — a header that re-tests, and a BACK EDGE.
// This is the shape a tree cannot hold: the body branches BACKWARDS to the header.
var n = 0
while n < 5 {
  n = n + 1
}
print(n)                  // 5

// a condition false on entry never runs the body: the header's first test takes the
// false edge straight to the exit, and the body block is still there, just never entered
var m = 0
while false {
  m = 99
}
print(m)                  // 0

// nested loops: two headers, two back edges, and the inner exit lands in the outer body
var i = 0
var total = 0
while i < 3 {
  var j = 0
  while j < 3 {
    total = total + 1
    j = j + 1
  }
  i = i + 1
}
print(total)              // 9
