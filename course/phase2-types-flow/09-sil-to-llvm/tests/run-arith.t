Programs RUN — the first time since Phase 1. `build` sends the IR through clang and produces a
native executable; these cases compile and execute it, so a mapping that merely prints is not
enough. Every number here is what `swiftc` prints for the same program (`oracle.t` re-checks
that on every run).

Integer arithmetic, precedence, and the sign rules Swift shares with C: division truncates
toward zero and the remainder takes the sign of the left operand.

  $ cat > a.swift <<'EOF'
  > print(1 + 2 * 3 - 10 / 2)
  > print((1 + 2) * 3)
  > print(20 / 6)
  > print(20 % 6)
  > print(-7 / 2)
  > print(-7 % 3)
  > print(7 % -3)
  > EOF
  $ ./lab.exe build a.swift -o a && ./a
  2
  9
  3
  2
  -3
  -1
  1

Unary minus, and a `let`/`var` round trip through its stack slot.

  $ cat > v.swift <<'EOF'
  > let a = 6
  > var c = a + 7
  > c = c * 2
  > print(-c)
  > print(-(2 - 5) * -2)
  > EOF
  $ ./lab.exe build v.swift -o v && ./v
  -26
  -6

`Bool` lowers to LLVM's `i1`, and `print` of one goes through the `select` between the two
string constants in the preamble, so it comes out as Swift spells it.

  $ cat > b.swift <<'EOF'
  > print(true)
  > print(false)
  > let n = 3
  > print(n > 1 && n < 5)
  > print(n > 5 || n == 3)
  > print(n > 5 && n < 1)
  > print(1 == 1)
  > print(2 >= 3)
  > EOF
  $ ./lab.exe build b.swift -o b && ./b
  true
  false
  true
  true
  false
  true
  false

Both `&&` and `||` short-circuit, which is a CFG property, not a bitwise one: the right operand
is only evaluated on the deciding edge.

  $ cat > sc.swift <<'EOF'
  > func loud(_ n: Int) -> Bool {
  >   print(n)
  >   return true
  > }
  > if false && loud(1) {
  >   print(9)
  > }
  > if true || loud(2) {
  >   print(8)
  > }
  > EOF
  $ ./lab.exe build sc.swift -o sc && ./sc
  8

A program that prints nothing still exits 0 — `@main`'s `ret i32 0` is the exit code.

  $ printf 'let x = 1\n' > q.swift
  $ ./lab.exe build q.swift -o q && ./q; echo "exit=$?"
  exit=0
