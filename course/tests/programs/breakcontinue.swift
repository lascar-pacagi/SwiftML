// Phase 2 / concept 08: `break` and `continue` — one branch each, but to WHICH block?
// Both read the innermost entry of the loop stack, and the two targets are different:
// break leaves by the exit, continue goes where the next trip starts.

// break: a branch to the loop's EXIT. The block holding it ends there, so the statements
// after it in the same block are unreachable and never lowered.
var n = 0
while n < 100 {
  n = n + 1
  if n > 3 {
    break
  }
}
print(n)                  // 4

// continue in a `while` goes back to the HEADER, which re-tests the condition
var i = 0
var odds = 0
while i < 10 {
  i = i + 1
  if i % 2 == 0 {
    continue
  }
  odds = odds + 1
}
print(odds)               // 5

// continue in a `for` goes to the LATCH, not the header — otherwise the increment is
// skipped and the loop never ends. This is the one that catches a wrong target.
var kept = 0
for j in 0 ..< 6 {
  if j == 2 {
    continue
  }
  kept = kept + 1
}
print(kept)               // 5

// in a nest, each one targets its OWN loop: the inner break leaves the inner loop only
var pairs = 0
for _ in 0 ..< 3 {
  for b in 0 ..< 3 {
    if b == 1 {
      break
    }
    pairs = pairs + 1
  }
}
print(pairs)              // 3
