TODO(36) — the forwarding rewrites. A slot whose value is already sitting in a register does not
need to be read from memory again: the reload becomes a `mov`, or disappears when the register
it would load into is the one already holding it.

A program that reuses two variables inside one block: with the pass on, the load count drops,
and the program still prints what it printed before.

  $ cat > s.swift <<'SWIFT'
  > let a = 7
  > let b = 11
  > print(a * a + a * b + b * b + a + b)
  > print(a * b * a + b * a * b)
  > SWIFT
  $ OFF=$(./lab.exe --emit-asm --no-peephole s.swift | grep -c '	ldr	'); ON=$(./lab.exe --emit-asm s.swift | grep -c '	ldr	'); test "$ON" -lt "$OFF" && echo "loads: $OFF -> $ON"
  loads: 18 -> 11
  $ ./lab.exe build s.swift --native -o s && ./s
  265
  1386
  $ swiftc -Onone s.swift -o s_sw && ./s_sw
  265
  1386

A store immediately followed by reloading the SAME register loses the reload entirely — nothing
replaces it, because the value is already where the load wanted to put it.

  $ cat > a.swift <<'SWIFT'
  > func fib(_ n: Int) -> Int { if n < 2 { return n }
  >   return fib(n - 1) + fib(n - 2) }
  > print(fib(20))
  > var s = 0
  > for i in 0 ..< 200 { s = s + i * i }
  > print(s)
  > print(100 / 7)
  > SWIFT
  $ ./lab.exe --emit-asm --no-peephole a.swift | grep -A1 'str	x19, \[sp, #24\]' | grep -c 'ldr	x19, \[sp, #24\]' || true
  1
  $ ./lab.exe --emit-asm a.swift | grep -A1 'str	x19, \[sp, #24\]' | grep -c 'ldr	x19, \[sp, #24\]' || true
  0

A reload into a DIFFERENT register becomes a register move — an instruction the CPU's renamer
largely makes free, where the load was a trip to the cache.

  $ ./lab.exe --emit-asm --no-peephole s.swift | grep -c '	mov	x[0-9]*, x' || true
  0
  $ ./lab.exe --emit-asm s.swift | grep -c '	mov	x[0-9]*, x' || true
  6

The rewritten code still matches swiftc, and still matches the backend with the pass switched
off — the two things an optimization has to prove.

  $ ./lab.exe build a.swift --native -o a && ./a
  6765
  2646700
  14
  $ ./lab.exe build a.swift --native --no-peephole -o a0 && ./a0
  6765
  2646700
  14
  $ swiftc -Onone a.swift -o a_sw && ./a_sw
  6765
  2646700
  14
