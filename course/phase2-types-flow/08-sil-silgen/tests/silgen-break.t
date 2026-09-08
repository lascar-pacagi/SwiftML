TODO(08c) — `break`, a branch to the enclosing loop's EXIT block. It needs the loop holes too:
`b.loops` is only pushed by `while` and `for`, so this file stays red until one of them is
built. Everything here is about which block the branch names.

`break` inside a `while` terminates its block with a `br` to the loop's exit — the same block
the header's false edge goes to.

  $ printf 'var n = 0\nwhile n < 10 {\n  n = n + 1\n  if n > 3 {\n    break\n  }\n}\nprint(n)\n' > b.swift
  $ ./lab.exe --emit-sil-canon b.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 0
    %1 = alloc_stack $Int  // n
    store %0 to %1
    br bb1
  bb1:
    %3 = integer_literal $Int, 10
    %4 = load %1 $Int
    %5 = binop "<" %4, %3 $Bool
    cond_br %5, bb2, bb4
  bb2:
    %6 = integer_literal $Int, 1
    %7 = integer_literal $Int, 3
    %8 = load %1 $Int
    %9 = binop "+" %8, %6 $Int
    store %9 to %1
    %11 = load %1 $Int
    %12 = binop ">" %11, %7 $Bool
    cond_br %12, bb3, bb5
  bb3:
    br bb4
  bb4:
    %13 = load %1 $Int
    %14 = apply @print(%13)
    return
  bb5:
    br bb1
  }

`break` in a `for` leaves the loop without running the latch, so the increment is skipped on
the way out — the exit block is the target, not the latch.

  $ printf 'var s = 0\nfor i in 0 ..< 9 {\n  if i == 2 {\n    break\n  }\n  s = s + i\n}\nprint(s)\n' > bf.swift
  $ ./lab.exe --emit-sil-canon bf.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 0
    %1 = integer_literal $Int, 0
    %2 = integer_literal $Int, 9
    %3 = alloc_stack $Int  // s
    %4 = alloc_stack $Int  // i
    store %0 to %3
    store %1 to %4
    br bb1
  bb1:
    %7 = load %4 $Int
    %8 = binop "<" %7, %2 $Bool
    cond_br %8, bb2, bb4
  bb2:
    %9 = integer_literal $Int, 2
    %10 = load %4 $Int
    %11 = binop "==" %10, %9 $Bool
    cond_br %11, bb3, bb5
  bb3:
    br bb4
  bb4:
    %12 = load %3 $Int
    %13 = apply @print(%12)
    return
  bb5:
    %14 = integer_literal $Int, 1
    %15 = load %3 $Int
    %16 = load %4 $Int
    %17 = binop "+" %15, %16 $Int
    store %17 to %3
    %19 = load %4 $Int
    %20 = binop "+" %19, %14 $Int
    store %20 to %4
    br bb1
  }

In nested loops `break` leaves only the INNER one: it branches to the inner loop's exit, and
that block then carries on into the outer loop's latch.

  $ printf 'var s = 0\nfor i in 0 ..< 3 {\n  for j in 0 ..< 3 {\n    if j == 1 {\n      break\n    }\n    s = s + 1\n  }\n}\nprint(s)\n' > bn.swift
  $ ./lab.exe --emit-sil-canon bn.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 0
    %1 = integer_literal $Int, 0
    %2 = integer_literal $Int, 3
    %3 = alloc_stack $Int  // s
    %4 = alloc_stack $Int  // i
    %5 = alloc_stack $Int  // j
    store %0 to %3
    store %1 to %4
    br bb1
  bb1:
    %8 = load %4 $Int
    %9 = binop "<" %8, %2 $Bool
    cond_br %9, bb2, bb8
  bb2:
    %10 = integer_literal $Int, 0
    %11 = integer_literal $Int, 3
    store %10 to %5
    br bb3
  bb3:
    %13 = load %5 $Int
    %14 = binop "<" %13, %11 $Bool
    cond_br %14, bb4, bb6
  bb4:
    %15 = integer_literal $Int, 1
    %16 = load %5 $Int
    %17 = binop "==" %16, %15 $Bool
    cond_br %17, bb5, bb7
  bb5:
    br bb6
  bb6:
    %18 = integer_literal $Int, 1
    %19 = load %4 $Int
    %20 = binop "+" %19, %18 $Int
    store %20 to %4
    br bb1
  bb7:
    %22 = integer_literal $Int, 1
    %23 = integer_literal $Int, 1
    %24 = load %3 $Int
    %25 = binop "+" %24, %22 $Int
    store %25 to %3
    %27 = load %5 $Int
    %28 = binop "+" %27, %23 $Int
    store %28 to %5
    br bb3
  bb8:
    %30 = load %3 $Int
    %31 = apply @print(%30)
    return
  }

`while true { … break }` still gets a header test and a false edge to the exit — SILGen does
not know the condition is constant — and the `break` adds a second edge into that same block.

  $ printf 'while true {\n  if true {\n    break\n  }\n}\nprint(0)\n' > bt.swift
  $ ./lab.exe --emit-sil-canon bt.swift
  sil @main() -> $() {
  bb0:
    br bb1
  bb1:
    %0 = integer_literal $Bool, true
    cond_br %0, bb2, bb4
  bb2:
    %1 = integer_literal $Bool, true
    cond_br %1, bb3, bb5
  bb3:
    br bb4
  bb4:
    %2 = integer_literal $Int, 0
    %3 = apply @print(%2)
    return
  bb5:
    br bb1
  }
  $ ./lab.exe --emit-sil-canon bt.swift > /dev/null 2> verr.txt; echo "exit=$?"
  exit=0
  $ cat verr.txt
