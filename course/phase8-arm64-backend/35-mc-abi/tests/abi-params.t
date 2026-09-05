TODO(35b) — the CALLEE's half of the same contract: parameters nine and beyond are read back off
the stack, through `x29`. Like 35a, no case here runs until both holes are filled.

The callee reads its stack parameters at `[x29, #16 + 8*j]`. `x29` points at the frame record,
and the saved `fp`/`lr` sit between it and the incoming arguments — hence the `+16`. The caller
wrote the same bytes at `[sp, #8*j]` before the `bl`: one address, two names.

  $ cat > a.swift <<'SWIFT'
  > func s10(_ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int, _ a10: Int) -> Int {
  >   return a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10
  > }
  > print(s10(1, 2, 3, 4, 5, 6, 7, 8, 9, 10))
  > SWIFT
  $ ./lab.exe --emit-asm a.swift | sed -n '/^_s10:/,/^Ls10_0:/p'
  _s10:
  	sub	sp, sp, #16
  	stp	x29, x30, [sp, #0]
  	mov	x29, sp
  	sub	sp, sp, #480
  	str	x19, [sp, #408]
  	str	x20, [sp, #416]
  	str	x21, [sp, #424]
  	str	x22, [sp, #432]
  	str	x23, [sp, #440]
  	str	x24, [sp, #448]
  	str	x25, [sp, #456]
  	str	x26, [sp, #464]
  	str	x27, [sp, #472]
  	mov	x23, x0
  	mov	x9, x1
  	str	x9, [sp, #24]
  	mov	x19, x2
  	mov	x25, x3
  	mov	x27, x4
  	mov	x26, x5
  	mov	x24, x6
  	mov	x21, x7
  	ldr	x20, [x29, #16]
  	ldr	x22, [x29, #24]
  Ls10_0:

`x29` is not `sp` on purpose: the frame size is not known when instructions are selected — it
depends on how much the register allocator spills — but `x29` is set once, to a fixed point, so
these offsets are the same whatever the frame turns out to be.

  $ ./lab.exe --emit-asm a.swift | grep -E -c '	ldr	x[0-9]+, \[x29, #(16|24)\]' || true
  2
  $ ./lab.exe --emit-asm a.swift | grep -E -c 'ldr	x[0-9]+, \[x29' || true
  2

Parameters one through eight still arrive in registers, so a nine-parameter function reads
exactly one word off the stack.

  $ cat > nine.swift <<'SWIFT'
  > func n9(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ g: Int, _ h: Int, _ p: Int, _ q: Int) -> Int {
  >   return a * 100 + q
  > }
  > print(n9(1, 0, 0, 0, 0, 0, 0, 0, 7))
  > SWIFT
  $ ./lab.exe --emit-asm nine.swift | grep -E -c 'ldr	x[0-9]+, \[x29' || true
  1
  $ ./lab.exe build nine.swift --native -o nine && ./nine
  107
  $ swiftc -Onone nine.swift -o nine_sw && ./nine_sw
  107

A wide RECURSION is where the two halves are hardest to get right: each level writes the
outgoing area its own caller has already read from, and reads its own arguments from the level
above. It matches swiftc under all three register-allocation rungs.

  $ cat > rec.swift <<'SWIFT'
  > func chain(_ n: Int, _ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ g: Int, _ h: Int, _ p: Int, _ q: Int) -> Int {
  >   if n == 0 { return p + q }
  >   return chain(n - 1, a, b, c, d, e, g, h, p + 1, q + 2)
  > }
  > print(chain(5, 0, 0, 0, 0, 0, 0, 0, 0, 0))
  > SWIFT
  $ ./lab.exe build rec.swift --native --regalloc=stack -o r_s && ./r_s
  15
  $ ./lab.exe build rec.swift --native --regalloc=linscan -o r_l && ./r_l
  15
  $ ./lab.exe build rec.swift --native --regalloc=graphcolor -o r_g && ./r_g
  15
  $ swiftc -Onone rec.swift -o r_sw && ./r_sw
  15
