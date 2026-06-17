Peephole optimization: local redundant-load elimination over the final ARM64 stream.
RED until the TODO(36) hole (the within-block forwarding rules).

Peephole-optimized code still matches swiftc (and the un-optimized backend) — fib, loops, division:

  $ cat > a.swift <<'SWIFT'
  > func fib(_ n: Int) -> Int { if n < 2 { return n }
  >   return fib(n - 1) + fib(n - 2) }
  > print(fib(20))
  > var s = 0
  > for i in 0 ..< 200 { s = s + i * i }
  > print(s)
  > print(100 / 7)
  > SWIFT
  $ ./lab.exe build a.swift --native -o a && ./a
  6765
  2646700
  14
  $ ./lab.exe build a.swift --native --no-peephole -o a0 && ./a0
  6765
  2646700
  14

On straight-line code that reuses variables, the peephole turns redundant memory loads into
register moves — the load count drops (the moves the CPU largely renames away):

  $ cat > s.swift <<'SWIFT'
  > let a = 7
  > let b = 11
  > print(a * a + a * b + b * b + a + b)
  > print(a * b * a + b * a * b)
  > SWIFT
  $ ./lab.exe build s.swift --native -o s && ./s
  265
  1386
  $ OFF=$(./lab.exe --emit-asm --no-peephole s.swift | grep -c '	ldr	')
  $ ON=$(./lab.exe --emit-asm s.swift | grep -c '	ldr	')
  $ test "$ON" -lt "$OFF" && echo "loads: $OFF -> $ON (peephole cut memory reads)"
  loads: 18 -> 11 (peephole cut memory reads)

A store immediately followed by reloading the SAME register loses the reload entirely:

  $ ./lab.exe --emit-asm --no-peephole a.swift | grep -A1 'str	x19, \[sp, #24\]' | grep -c 'ldr	x19, \[sp, #24\]' || true
  1
  $ ./lab.exe --emit-asm a.swift | grep -A1 'str	x19, \[sp, #24\]' | grep -c 'ldr	x19, \[sp, #24\]' || true
  0
