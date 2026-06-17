Register allocation: the ladder stack -> linear-scan -> graph-colour over virtual-register ARM64.
RED until the TODO(34) holes (the linear-scan core and the graph-colouring core).

All three rungs produce a CORRECT native binary that matches swiftc — fib, loops, division:

  $ cat > a.swift <<'SWIFT'
  > func fib(_ n: Int) -> Int { if n < 2 { return n }
  >   return fib(n - 1) + fib(n - 2) }
  > print(fib(18))
  > var s = 0
  > for i in 0 ..< 50 { s = s + i * i }
  > print(s)
  > print(100 / 7)
  > print(13 % 4)
  > SWIFT
  $ ./lab.exe build a.swift --native --regalloc=stack -o a_s && ./a_s
  2584
  40425
  14
  1
  $ ./lab.exe build a.swift --native --regalloc=linscan -o a_l && ./a_l
  2584
  40425
  14
  1
  $ ./lab.exe build a.swift --native --regalloc=graphcolor -o a_g && ./a_g
  2584
  40425
  14
  1

The stack rung spills EVERY value to memory; linear-scan and graph-colour keep values in
registers, so they have far less load/store traffic:

  $ S=$(./lab.exe --emit-asm --regalloc=stack a.swift | grep -E -c '	(ldr|str)	')
  $ G=$(./lab.exe --emit-asm --regalloc=graphcolor a.swift | grep -E -c '	(ldr|str)	')
  $ test "$G" -lt "$S" && echo "graphcolor ($G) < stack ($S) memory ops"
  graphcolor (41) < stack (95) memory ops

The stack rung uses NO callee-saved registers (everything is in slots); graph-colour allocates
them (and the prologue saves the ones it used):

  $ ./lab.exe --emit-asm --regalloc=stack a.swift | grep -E -c 'x(19|2[0-7])' || true
  0
  $ ./lab.exe --emit-asm --regalloc=graphcolor a.swift | grep -E -c 'x(19|2[0-7])' || true
  77

linear-scan also keeps values in registers (same low memory traffic as graph-colour on this
low-pressure code):

  $ ./lab.exe --emit-asm --regalloc=linscan a.swift | grep -E -c '	(ldr|str)	' || true
  41

The native backend still agrees with the LLVM backend (Backend A):

  $ ./lab.exe build a.swift -o a_llvm && ./a_g > o_native && ./a_llvm > o_llvm
  $ diff o_native o_llvm && echo SAME
  SAME
