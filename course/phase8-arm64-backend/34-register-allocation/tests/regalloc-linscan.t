TODO(34a) — linear scan. Live intervals sorted by start, a pool of nine callee-saved registers,
and the interval that ends LATEST evicted when the pool runs dry. Every case here runs
`--regalloc=linscan`, so the whole file stays TODO until the hole is filled.

Linear scan compiles fib, a loop and integer division to a native binary that matches swiftc.

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
  $ ./lab.exe build a.swift --native --regalloc=linscan -o a_l && ./a_l
  2584
  40425
  14
  1

Values live in registers now, so linear scan does far less memory traffic than the stack rung.

  $ S=$(./lab.exe --emit-asm --regalloc=stack a.swift | grep -E -c '	(ldr|str)	'); L=$(./lab.exe --emit-asm --regalloc=linscan a.swift | grep -E -c '	(ldr|str)	'); test "$L" -lt "$S" && echo "linscan ($L) < stack ($S) memory ops"
  linscan (41) < stack (95) memory ops

The pool is x19-x27 — callee-saved, so an allocated value survives a `bl` with no extra work.
The stack rung, which keeps nothing in a register, touches none of them.

  $ ./lab.exe --emit-asm --regalloc=stack a.swift | grep -E -c 'x(19|2[0-7])' || true
  0
  $ ./lab.exe --emit-asm --regalloc=linscan a.swift | grep -E -c 'x(19|2[0-7])' || true
  77

`_fib`'s prologue shows the whole frame contract: push the record, point x29 at it, carve the
locals, then save every callee-saved register the allocator handed out — so a caller that had
values in them gets them back at the `ret`.

  $ ./lab.exe --emit-asm --regalloc=linscan a.swift | sed -n '/^_fib:/,$p' | head -8
  _fib:
  	sub	sp, sp, #16
  	stp	x29, x30, [sp, #0]
  	mov	x29, sp
  	sub	sp, sp, #192
  	str	x19, [sp, #160]
  	str	x20, [sp, #168]
  	str	x21, [sp, #176]

Fourteen variables and a seven-term product still match swiftc. (Raw SIL keeps variables in
memory, so this is broad correctness, not pressure — the eviction rule itself is driven past the
nine-register pool by the alcotest suite, on a hand-built instruction stream.)

  $ cat > pressure.swift <<'SWIFT'
  > let a = 1
  > let b = 2
  > let c = 3
  > let d = 4
  > let e = 5
  > let f = 6
  > let g = 7
  > let h = 8
  > let i = 9
  > let j = 10
  > let k = 11
  > let l = 12
  > let m = 13
  > let n = 14
  > print(a+b+c+d+e+f+g+h+i+j+k+l+m+n)
  > print(a*n + b*m + c*l + d*k + e*j + f*i + g*h)
  > SWIFT
  $ ./lab.exe build pressure.swift --native --regalloc=linscan -o p_l && ./p_l
  105
  280
  $ swiftc -Onone pressure.swift -o p_sw && ./p_sw
  105
  280

Backend B under linear scan agrees with Backend A, the LLVM path, on the same program.

  $ ./lab.exe build a.swift -o a_llvm && ./a_l > o_l && ./a_llvm > o_llvm
  $ diff o_l o_llvm && echo SAME
  SAME
