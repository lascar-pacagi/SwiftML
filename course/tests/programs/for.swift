// Phase 2 / concept 08: `for` DESUGARED to a counted loop.
// `for` adds no new SIL. Read it as four blocks: a slot for the variable seeded with `lo`,
// a HEADER testing it against `hi`, a BODY, and a LATCH that increments and carries the
// back edge — the latch is separate so that `continue` can reach it instead of skipping it.
for i in 0 ..< 4 {
  print(i)                // 0 1 2 3
}

// the bound is evaluated ONCE, before the loop: `k + 1` is computed in the entry block,
// not recomputed on every trip
let k = 2
for i in 0 ..< k + 1 {
  print(i)                // 0 1 2
}

// an empty range never enters the body — the header's first test already fails
for i in 3 ..< 3 {
  print(i)
}

// nested: the inner loop's exit block is where the outer body carries on
var cells = 0
for _ in 0 ..< 3 {
  for _ in 0 ..< 4 {
    cells = cells + 1
  }
}
print(cells)              // 12
