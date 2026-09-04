TODO(08) — `continue`, a branch to the enclosing loop's CONTINUE target. Like `break` it needs
a loop hole first. The target is the loop's header for a `while`, and the LATCH for a `for` —
getting that wrong compiles to an infinite loop, and this file is where it shows.

`continue` in a `while` branches back to the header, which is also where the body's
fall-through goes.

  $ printf 'var n = 0\nwhile n < 5 {\n  n = n + 1\n  if n == 2 {\n    continue\n  }\n  print(n)\n}\n' > c.swift
  $ ./lab.exe --emit-sil c.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 0
    %1 = alloc_stack $Int  // n
    store %0 to %1
    br bb1
  bb1:
    %3 = load %1 $Int
    %4 = integer_literal $Int, 5
    %5 = binop "<" %3, %4 $Bool
    cond_br %5, bb2, bb3
  bb2:
    %6 = load %1 $Int
    %7 = integer_literal $Int, 1
    %8 = binop "+" %6, %7 $Int
    store %8 to %1
    %10 = load %1 $Int
    %11 = integer_literal $Int, 2
    %12 = binop "==" %10, %11 $Bool
    cond_br %12, bb4, bb5
  bb3:
    return
  bb4:
    br bb1
  bb5:
    %13 = load %1 $Int
    %14 = apply @print(%13)
    br bb1
  }

`continue` in a `for` branches to the LATCH, not the header, so `i = i + 1` still runs — a
branch to the header here would loop forever on the value that triggered the `continue`.

  $ printf 'for i in 0 ..< 5 {\n  if i == 2 {\n    continue\n  }\n  print(i)\n}\n' > cf.swift
  $ ./lab.exe --emit-sil cf.swift
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
    cond_br %5, bb2, bb4
  bb2:
    %6 = load %2 $Int
    %7 = integer_literal $Int, 2
    %8 = binop "==" %6, %7 $Bool
    cond_br %8, bb5, bb6
  bb3:
    %11 = load %2 $Int
    %12 = integer_literal $Int, 1
    %13 = binop "+" %11, %12 $Int
    store %13 to %2
    br bb1
  bb4:
    return
  bb5:
    br bb3
  bb6:
    %9 = load %2 $Int
    %10 = apply @print(%9)
    br bb3
  }

Two blocks branch to the latch — the `continue` above, and the body's fall-through — so the
increment is written once and reached from both paths.

  $ ./lab.exe --emit-sil cf.swift | grep -c "br bb3" || true
  2

In nested loops `continue` targets the inner loop, so the outer counter is untouched.

  $ printf 'var s = 0\nfor i in 0 ..< 3 {\n  for j in 0 ..< 3 {\n    if j == 1 {\n      continue\n    }\n    s = s + 1\n  }\n}\nprint(s)\n' > cn.swift
  $ ./lab.exe --emit-sil cn.swift
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
    br bb7
  bb10:
    %18 = load %1 $Int
    %19 = integer_literal $Int, 1
    %20 = binop "+" %18, %19 $Int
    store %20 to %1
    br bb7
  }

The verifier accepts it: every `continue` names a block that exists.

  $ ./lab.exe --emit-sil cn.swift > /dev/null 2> verr.txt; echo "exit=$?"
  exit=0
  $ cat verr.txt
