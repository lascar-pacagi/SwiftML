Machine code & the AAPCS64 / Apple ABI: arguments beyond 8 go on the stack; a large-frame-safe
prologue. RED until the TODO(35) holes (stack-passed argument placement + parameter loading).

A 10-argument function — the 9th and 10th go on the stack — runs and matches swiftc:

  $ cat > a.swift <<'SWIFT'
  > func s10(_ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int, _ a10: Int) -> Int {
  >   return a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10
  > }
  > print(s10(1, 2, 3, 4, 5, 6, 7, 8, 9, 10))
  > print(s10(10, 20, 30, 40, 50, 60, 70, 80, 90, 100))
  > SWIFT
  $ ./lab.exe build a.swift --native -o a && ./a
  55
  550

A 12-argument function with weighted sums — all three rungs agree with swiftc:

  $ cat > w.swift <<'SWIFT'
  > func f(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ g: Int, _ h: Int, _ p: Int, _ q: Int, _ r: Int, _ s: Int, _ t: Int) -> Int {
  >   return a*1 + b*2 + c*3 + d*4 + e*5 + g*6 + h*7 + p*8 + q*9 + r*10 + s*11 + t*12
  > }
  > print(f(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1))
  > print(f(2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
  > SWIFT
  $ ./lab.exe build w.swift --native --regalloc=stack -o w_s && ./w_s
  78
  38
  $ ./lab.exe build w.swift --native --regalloc=graphcolor -o w_g && ./w_g
  78
  38

The call site stores the 9th/10th arguments to the outgoing area; the callee reads its stack
parameters via x29 (the incoming sp):

  $ ./lab.exe --emit-asm a.swift | grep -E -c '	str	x[0-9]+, \[sp, #(0|8)\]' || true
  6
  $ ./lab.exe --emit-asm a.swift | grep -E -c 'ldr	x[0-9]+, \[x29, #(16|24)\]' || true
  2

The prologue is large-frame-safe — fp/lr are pushed first (offset 0), then the locals allocated,
so `stp`/`ldp` never exceed their immediate range even on a big frame:

  $ ./lab.exe --emit-asm w.swift | grep -c 'stp	x29, x30, \[sp, #0\]' || true
  2

Functions with <= 8 arguments are unchanged and still match swiftc:

  $ cat > s.swift <<'SWIFT'
  > func fib(_ n: Int) -> Int { if n < 2 { return n }
  >   return fib(n - 1) + fib(n - 2) }
  > print(fib(20))
  > SWIFT
  $ ./lab.exe build s.swift --native -o s && ./s
  6765
