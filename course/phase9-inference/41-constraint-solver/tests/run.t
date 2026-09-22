The programs RUN. This is the file that can tell one overload from another: every case here
type-checks whichever declaration you pick, and only the number it prints says which one the
solver actually chose. Goes green with TODO(41a-d).

Three declarations of `show`, differing only in the parameter type, each returning a
different number. The output IS the resolution: 1, 2, 3 in that order means #0, #1, #2.

  $ cat > ovl.swift <<'EOF'
  > func show(_ x: Int) -> Int { return 1 }
  > func show(_ x: Double) -> Int { return 2 }
  > func show(_ x: String) -> Int { return 3 }
  > print(show(1))
  > print(show(1.5))
  > print(show("x"))
  > print(show(1 + 2))
  > EOF
  $ ./lab.exe build ovl.swift -o ovl && ./ovl
  1
  2
  3
  1

Overloaded on the RETURN TYPE alone. Both calls are written `g()`; the annotation is the
only thing that differs, and the program prints 10 to prove the Int one ran.

  $ cat > ret.swift <<'EOF'
  > func g() -> Int { return 10 }
  > func g() -> Double { return 2.5 }
  > let d: Int = g()
  > print(d)
  > EOF
  $ ./lab.exe build ret.swift -o ret && ./ret
  10

Overloaded on arity, which is settled before the search even begins.

  $ cat > arity.swift <<'EOF'
  > func k(_ x: Int) -> Int { return x }
  > func k(_ x: Int, _ y: Int) -> Int { return x + y }
  > print(k(7))
  > print(k(3, 4))
  > EOF
  $ ./lab.exe build arity.swift -o arity && ./arity
  7
  7

And the rest of the language still works, because only the checker changed: recursion,
control flow, and a function whose result feeds a condition.

  $ cat > rest.swift <<'EOF'
  > func fib(_ n: Int) -> Int { if n < 2 { return n }
  > return fib(n - 1) + fib(n - 2) }
  > func cmp(_ a: Int, _ b: Int) -> Bool { return a < b }
  > print(fib(15))
  > if cmp(2, 3) { print(1) } else { print(0) }
  > var n = 0
  > while n < 5 { n = n + 1 }
  > print(n)
  > EOF
  $ ./lab.exe build rest.swift -o rest && ./rest
  610
  1
  5
