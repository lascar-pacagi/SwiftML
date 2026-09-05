TODO(34b) — graph colouring. The interference graph from interval overlap, Chaitin-Briggs
simplify (repeatedly remove a node of degree < K and push it), then select (pop and give each
node a colour none of its neighbours has). It is the DEFAULT rung, so a plain `build --native`
exercises it too, and the whole file stays TODO until the hole is filled.

Graph colouring compiles fib, a loop and integer division to a native binary matching swiftc.

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
  $ ./lab.exe build a.swift --native --regalloc=graphcolor -o a_g && ./a_g
  2584
  40425
  14
  1

`--regalloc` is optional: graph colouring is what a plain `build --native` picks.

  $ ./lab.exe build a.swift --native -o a_default && ./a_default > o_default && ./a_g > o_g
  $ diff o_default o_g && echo "default = graphcolor"
  default = graphcolor

It keeps values in registers, so its memory traffic is far below the stack rung's.

  $ S=$(./lab.exe --emit-asm --regalloc=stack a.swift | grep -E -c '	(ldr|str)	'); G=$(./lab.exe --emit-asm --regalloc=graphcolor a.swift | grep -E -c '	(ldr|str)	'); test "$G" -lt "$S" && echo "graphcolor ($G) < stack ($S) memory ops"
  graphcolor (41) < stack (95) memory ops

It allocates out of the callee-saved pool x19-x27, which the stack rung never touches.

  $ ./lab.exe --emit-asm --regalloc=graphcolor a.swift | grep -E -c 'x(19|2[0-7])' || true
  77

Fourteen variables and a seven-term product still match swiftc. (Running simplify out of
low-degree nodes, and checking that no two overlapping intervals ever share a colour, both
happen in the alcotest suite, against the interference relation directly.)

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
  $ ./lab.exe build pressure.swift --native --regalloc=graphcolor -o p_g && ./p_g
  105
  280
  $ swiftc -Onone pressure.swift -o p_sw && ./p_sw
  105
  280

A big frame still assembles. The frame record is pushed FIRST and stored at offset 0, because
`stp`/`ldp` take a 7-bit signed immediate scaled by 8 (-512..+504): the older prologue's `stp
x29, x30, [sp, #frame-16]` stopped assembling once the locals passed about half a kilobyte, and
under the default allocator a forty-`let` main was enough. No `stp`/`ldp` in the output may use
a nonzero offset.

  $ i=0; sum=""; : > many.swift
  > while [ $i -lt 40 ]; do echo "let v$i = $i" >> many.swift; sum="$sum+v$i"; i=$((i+1)); done
  > echo "print(0$sum)" >> many.swift
  $ ./lab.exe --emit-asm --regalloc=graphcolor many.swift | grep -E '	(stp|ldp)	' | grep -E -c -v '#0\]' || true
  0
  $ ./lab.exe build many.swift --native -o many_g && ./many_g
  780
  $ swiftc -Onone many.swift -o many_sw && ./many_sw
  780

Backend B under graph colouring agrees with Backend A, the LLVM path, on the same program.

  $ ./lab.exe build a.swift -o a_llvm && ./a_llvm > o_llvm
  $ diff o_g o_llvm && echo SAME
  SAME
