TODO(08) — `break`, a branch to the enclosing loop's EXIT block. It needs the loop holes too:
`b.loops` is only pushed by `while` and `for`, so this file stays red until one of them is
built. Everything here is about which block the branch names.

`break` inside a `while` terminates its block with a `br` to the loop's exit — the same block
the header's false edge goes to.

  $ printf 'var n = 0\nwhile n < 10 {\n  n = n + 1\n  if n > 3 {\n    break\n  }\n}\nprint(n)\n' > b.swift
  $ ./lab.exe --emit-sil b.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 0
    %1 = alloc_stack $Int  // n
    store %0 to %1
    br bb1
  bb1:
    %3 = load %1 $Int
    %4 = integer_literal $Int, 10
    %5 = binop "<" %3, %4 $Bool
    cond_br %5, bb2, bb3
  bb2:
    %6 = load %1 $Int
    %7 = integer_literal $Int, 1
    %8 = binop "+" %6, %7 $Int
    store %8 to %1
    %10 = load %1 $Int
    %11 = integer_literal $Int, 3
    %12 = binop ">" %10, %11 $Bool
    cond_br %12, bb4, bb5
  bb3:
    %13 = load %1 $Int
    %14 = apply @print(%13)
    return
  bb4:
    br bb3
  bb5:
    br bb1
  }

`break` in a `for` leaves the loop without running the latch, so the increment is skipped on
the way out — the exit block is the target, not the latch.

  $ printf 'var s = 0\nfor i in 0 ..< 9 {\n  if i == 2 {\n    break\n  }\n  s = s + i\n}\nprint(s)\n' > bf.swift
  $ ./lab.exe --emit-sil bf.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 0
    %1 = alloc_stack $Int  // s
    store %0 to %1
    %3 = integer_literal $Int, 0
    %4 = integer_literal $Int, 9
    %5 = alloc_stack $Int  // i
    store %3 to %5
    br bb1
  bb1:
    %7 = load %5 $Int
    %8 = binop "<" %7, %4 $Bool
    cond_br %8, bb2, bb4
  bb2:
    %9 = load %5 $Int
    %10 = integer_literal $Int, 2
    %11 = binop "==" %9, %10 $Bool
    cond_br %11, bb5, bb6
  bb3:
    %16 = load %5 $Int
    %17 = integer_literal $Int, 1
    %18 = binop "+" %16, %17 $Int
    store %18 to %5
    br bb1
  bb4:
    %20 = load %1 $Int
    %21 = apply @print(%20)
    return
  bb5:
    br bb4
  bb6:
    %12 = load %1 $Int
    %13 = load %5 $Int
    %14 = binop "+" %12, %13 $Int
    store %14 to %1
    br bb3
  }

In nested loops `break` leaves only the INNER one: it branches to the inner loop's exit, and
that block then carries on into the outer loop's latch.

  $ printf 'var s = 0\nfor i in 0 ..< 3 {\n  for j in 0 ..< 3 {\n    if j == 1 {\n      break\n    }\n    s = s + 1\n  }\n}\nprint(s)\n' > bn.swift
  $ ./lab.exe --emit-sil bn.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 0
    %1 = alloc_stack $Int  // s
    store %0 to %1
    %3 = integer_literal $Int, 0
    %4 = integer_literal $Int, 3
    %5 = alloc_stack $Int  // i
    store %3 to %5
    br bb1
  bb1:
    %7 = load %5 $Int
    %8 = binop "<" %7, %4 $Bool
    cond_br %8, bb2, bb4
  bb2:
    %9 = integer_literal $Int, 0
    %10 = integer_literal $Int, 3
    %11 = alloc_stack $Int  // j
    store %9 to %11
    br bb5
  bb3:
    %26 = load %5 $Int
    %27 = integer_literal $Int, 1
    %28 = binop "+" %26, %27 $Int
    store %28 to %5
    br bb1
  bb4:
    %30 = load %1 $Int
    %31 = apply @print(%30)
    return
  bb5:
    %13 = load %11 $Int
    %14 = binop "<" %13, %10 $Bool
    cond_br %14, bb6, bb8
  bb6:
    %15 = load %11 $Int
    %16 = integer_literal $Int, 1
    %17 = binop "==" %15, %16 $Bool
    cond_br %17, bb9, bb10
  bb7:
    %22 = load %11 $Int
    %23 = integer_literal $Int, 1
    %24 = binop "+" %22, %23 $Int
    store %24 to %11
    br bb5
  bb8:
    br bb3
  bb9:
    br bb8
  bb10:
    %18 = load %1 $Int
    %19 = integer_literal $Int, 1
    %20 = binop "+" %18, %19 $Int
    store %20 to %1
    br bb7
  }

`while true { … break }` still gets a header test and a false edge to the exit — SILGen does
not know the condition is constant — and the `break` adds a second edge into that same block.

  $ printf 'while true {\n  if true {\n    break\n  }\n}\nprint(0)\n' > bt.swift
  $ ./lab.exe --emit-sil bt.swift
  sil @main() -> $() {
  bb0:
    br bb1
  bb1:
    %0 = integer_literal $Bool, true
    cond_br %0, bb2, bb3
  bb2:
    %1 = integer_literal $Bool, true
    cond_br %1, bb4, bb5
  bb3:
    %2 = integer_literal $Int, 0
    %3 = apply @print(%2)
    return
  bb4:
    br bb3
  bb5:
    br bb1
  }
  $ ./lab.exe --emit-sil bt.swift > /dev/null 2> verr.txt; echo "exit=$?"
  exit=0
  $ cat verr.txt
