Backend B — the from-scratch ARM64 backend. SIL -> isel -> ARM64 asm -> clang(as/ld) -> native.
RED until the TODO(33) holes (the instruction-selection templates: sel_instr + sel_term).

A native ARM64 executable runs and matches swiftc — arithmetic, control flow, recursion, print:

  $ cat > a.swift <<'SWIFT'
  > func fib(_ n: Int) -> Int {
  >   if n < 2 { return n }
  >   return fib(n - 1) + fib(n - 2)
  > }
  > print(fib(15))
  > var s = 0
  > for i in 0 ..< 10 { s = s + i * i }
  > print(s)
  > print(100 / 7)
  > print(100 % 7)
  > let ok = 3 > 2
  > print(ok)
  > SWIFT
  $ ./lab.exe build a.swift --native -o a && ./a
  610
  285
  14
  2
  true

The emitted assembly is real ARM64 (Apple/macOS): a stack-frame prologue, the printf call with
its variadic arg on the stack, and a `bl` to the recursive function:

  $ ./lab.exe --emit-asm a.swift | grep -c 'stp\tx29, x30' || true
  2
  $ ./lab.exe --emit-asm a.swift | grep -E -c '\tbl\t_fib' || true
  3
  $ ./lab.exe --emit-asm a.swift | grep -E -c '\tbl\t_printf' || true
  5
  $ ./lab.exe --emit-asm a.swift | grep -E -c '\tsdiv\t|\tmsub\t|\tmul\t' || true
  4

Comparisons lower to cmp + cset; the format string is in the cstring section:

  $ ./lab.exe --emit-asm a.swift | grep -c '\tcset\t' || true
  3
  $ ./lab.exe --emit-asm a.swift | grep -c '__TEXT,__cstring' || true
  1

The native backend agrees with the LLVM backend (Backend A) on the same program — two backends,
one front end:

  $ ./lab.exe build a.swift -o b && ./a > out_native && ./b > out_llvm
  $ diff out_native out_llvm && echo SAME
  SAME
