End-to-end: compile a program, run it, check stdout. Needs every hole in `irgen.ml` (the
unit suite `test_irgen.ml` reaches each one alone). Every expected value here is what swiftc
prints for the same file; `oracle.t` re-asks swiftc each run.

`1 + 2 * 3` is 7, `(1 + 2) * 3` is 9, `20 / 6` is 3, `20 % 6` is 2, `-5 + 8` is 3:

  $ cat > a.swift <<'EOF'
  > print(1 + 2 * 3)
  > print((1 + 2) * 3)
  > print(20 / 6)
  > print(20 % 6)
  > print(-5 + 8)
  > EOF
  $ ./lab.exe build a.swift -o a && ./a
  7
  9
  3
  2
  3

Negative results: `-7 / 2` is -3 and `-7 % 3` is -1 — `sdiv`/`srem`, never `udiv`/`urem`.
Integer division truncates toward zero and the remainder takes the sign of the DIVIDEND
(Python's floored `%` would say 2). `print(-(2 + 3))` is avoided on purpose: swiftc rejects
prefix `-` on an untyped parenthesised literal as ambiguous, our Int-only checker cannot:

  $ cat > b.swift <<'EOF'
  > print(2 + 3 * 4 - 10 / 2)
  > let n = 2 + 3
  > print(-n)
  > print(3 - 10)
  > print(-7 % 3)
  > print(7 % -3)
  > print(-7 / 2)
  > print(2 * -3 + 1)
  > EOF
  $ ./lab.exe build b.swift -o b && ./b
  9
  -5
  -7
  -1
  1
  -3
  -5

Every operator in one line, chained `/` and `%` left-to-right, a ten-term sum:

  $ cat > hard.swift <<'EOF'
  > print(1 + 2 * 3 - 8 / 4 % 3)
  > print(-(2 - 5) * -2)
  > print(100 / 5 / 2)
  > print(10 % 7 % 2)
  > print(2 * (3 + 4) * 5)
  > print(1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10)
  > EOF
  $ ./lab.exe build hard.swift -o hard && ./hard
  5
  -6
  10
  1
  70
  55

A program that prints nothing exits 0 and stays silent:

  $ printf 'let a = 1\n' > quiet.swift
  $ ./lab.exe build quiet.swift -o quiet && ./quiet; echo "exit=$?"
  exit=0
