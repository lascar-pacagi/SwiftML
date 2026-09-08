TODO(08c) — `continue`, a branch to the enclosing loop's CONTINUE target. Like `break` it needs
a loop hole first. The target is the loop's header for a `while`, and the LATCH for a `for` —
getting that wrong compiles to an infinite loop, and this file is where it shows.

`continue` in a `while` branches back to the header, which is also where the body's
fall-through goes.

  $ printf 'var n = 0\nwhile n < 5 {\n  n = n + 1\n  if n == 2 {\n    continue\n  }\n  print(n)\n}\n' > c.swift
  $ ./lab.exe --emit-sil-canon c.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 0
    %1 = alloc_stack $Int  // n
    store %0 to %1
    br bb1
  bb1:
    %3 = integer_literal $Int, 5
    %4 = load %1 $Int
    %5 = binop "<" %4, %3 $Bool
    cond_br %5, bb2, bb5
  bb2:
    %6 = integer_literal $Int, 1
    %7 = integer_literal $Int, 2
    %8 = load %1 $Int
    %9 = binop "+" %8, %6 $Int
    store %9 to %1
    %11 = load %1 $Int
    %12 = binop "==" %11, %7 $Bool
    cond_br %12, bb3, bb4
  bb3:
    br bb1
  bb4:
    %13 = load %1 $Int
    %14 = apply @print(%13)
    br bb1
  bb5:
    return
  }

`continue` in a `for` branches to the LATCH, not the header, so `i = i + 1` still runs — a
branch to the header here would loop forever on the value that triggered the `continue`.

  $ printf 'for i in 0 ..< 5 {\n  if i == 2 {\n    continue\n  }\n  print(i)\n}\n' > cf.swift
  $ ./lab.exe --emit-sil-canon cf.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 0
    %1 = integer_literal $Int, 5
    %2 = alloc_stack $Int  // i
    store %0 to %2
    br bb1
  bb1:
    %4 = load %2 $Int
    %5 = binop "<" %4, %1 $Bool
    cond_br %5, bb2, bb6
  bb2:
    %6 = integer_literal $Int, 2
    %7 = load %2 $Int
    %8 = binop "==" %7, %6 $Bool
    cond_br %8, bb3, bb5
  bb3:
    br bb4
  bb4:
    %9 = integer_literal $Int, 1
    %10 = load %2 $Int
    %11 = binop "+" %10, %9 $Int
    store %11 to %2
    br bb1
  bb5:
    %13 = load %2 $Int
    %14 = apply @print(%13)
    br bb4
  bb6:
    return
  }

Two blocks branch to the latch — the `continue` above, and the body's fall-through — so the
increment is written once and reached from both paths.

  $ ./lab.exe --emit-sil-canon cf.swift | grep -c "br bb3" || true
  0

In nested loops `continue` targets the inner loop, so the outer counter is untouched.

  $ printf 'var s = 0\nfor i in 0 ..< 3 {\n  for j in 0 ..< 3 {\n    if j == 1 {\n      continue\n    }\n    s = s + 1\n  }\n}\nprint(s)\n' > cn.swift
  $ ./lab.exe --emit-sil-canon cn.swift
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
    cond_br %9, bb2, bb9
  bb2:
    %10 = integer_literal $Int, 0
    %11 = integer_literal $Int, 3
    store %10 to %5
    br bb3
  bb3:
    %13 = load %5 $Int
    %14 = binop "<" %13, %11 $Bool
    cond_br %14, bb4, bb8
  bb4:
    %15 = integer_literal $Int, 1
    %16 = load %5 $Int
    %17 = binop "==" %16, %15 $Bool
    cond_br %17, bb5, bb7
  bb5:
    br bb6
  bb6:
    %18 = integer_literal $Int, 1
    %19 = load %5 $Int
    %20 = binop "+" %19, %18 $Int
    store %20 to %5
    br bb3
  bb7:
    %22 = integer_literal $Int, 1
    %23 = load %3 $Int
    %24 = binop "+" %23, %22 $Int
    store %24 to %3
    br bb6
  bb8:
    %26 = integer_literal $Int, 1
    %27 = load %4 $Int
    %28 = binop "+" %27, %26 $Int
    store %28 to %4
    br bb1
  bb9:
    %30 = load %3 $Int
    %31 = apply @print(%30)
    return
  }

The verifier accepts it: every `continue` names a block that exists.

  $ ./lab.exe --emit-sil-canon cn.swift > /dev/null 2> verr.txt; echo "exit=$?"
  exit=0
  $ cat verr.txt
