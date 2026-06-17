End-to-end: compile a program with swiftml, run it, check stdout. This is self-contained
(no swiftc needed); `make oracle F=…` does the swiftc parity check separately. Every
expected value below also matches `swiftc` (verified in the lab's solution checks).

RED until you implement `irgen.ml : emit_llvm` (in the concept directory; needs 01–03).

Arithmetic with precedence, parens, division, remainder, unary minus:

  $ cat > a.swift <<'EOF'
  > print(1 + 2 * 3)
  > print((1 + 2) * 3)
  > print(20 / 6)
  > print(20 % 6)
  > print(-5 + 8)
  > EOF
  $ swiftml build a.swift -o a && ./a
  7
  9
  3
  2
  3

Negative results, unary minus on a binding, deep precedence, and the sign rules for `/`
and `%` (truncate toward zero; remainder takes the sign of the dividend — these must match
swiftc, not Python's floored `%`). (`print(-(2 + 3))` is intentionally avoided: swiftc
rejects prefix `-` on an untyped parenthesised literal as ambiguous; Phase 1's Int-only
checker can't see that, so we keep the corpus inside the subset both compilers accept.)

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
  $ swiftml build b.swift -o b && ./b
  9
  -5
  -7
  -1
  1
  -3
  -5

let/var bindings, references, reassignment:

  $ cat > v.swift <<'EOF'
  > let a = 6
  > var c = a + 7
  > c = c * 2
  > print(c)
  > EOF
  $ swiftml build v.swift -o v && ./v
  26

Reassignment really mutates the slot, and later reads see the new value:

  $ cat > w.swift <<'EOF'
  > var x = 1
  > x = x + 4
  > x = x * x
  > print(x)
  > let y = x - 5
  > print(y)
  > EOF
  $ swiftml build w.swift -o w && ./w
  25
  20
