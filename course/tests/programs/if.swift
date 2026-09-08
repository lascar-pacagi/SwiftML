// Phase 2 / concept 08: the `if` DIAMOND, and the three shapes it takes.
// Read the SIL: each `if` is a cond_br into two blocks that both br to a merge.
//
// `n` comes from a call so neither compiler can decide the branches in advance — otherwise
// swiftc folds them and warns that a block will never be executed.
func seven() -> Int {
  return 7
}
let n = seven()

// with an else: then, else, merge — three blocks, both arms branching to the third
if n < 5 {
  print(1)
} else {
  print(2)
}

// without an else: only two blocks, because the FALSE edge *is* the merge
if n > 5 {
  print(3)
}

// an else-if chain is an `if` inside the else block, so the diamonds nest
if n == 1 {
  print(10)
} else if n == 7 {
  print(11)
} else {
  print(12)
}

// both arms return, so the merge is genuinely unreachable and keeps `unreachable`
func sign(_ x: Int) -> Int {
  if x < 0 {
    return -1
  } else {
    return 1
  }
}
print(sign(-4))
print(sign(9))
