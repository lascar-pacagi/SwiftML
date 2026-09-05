TODO(35a) — the CALLER's half of the contract: arguments nine and beyond are written into the
outgoing stack-arg area at the bottom of the caller's frame. The two holes are two ends of one
agreement, so neither side runs alone: every case here needs 35b filled too, and the file reads
TODO until both are.

Argument 9 of a ten-argument call goes to `[sp, #0]` and argument 10 to `[sp, #8]` — the very
bottom of the frame, which is also where `print` puts its variadic argument, so the area is
never smaller than two words.

  $ cat > a.swift <<'SWIFT'
  > func s10(_ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int, _ a10: Int) -> Int {
  >   return a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10
  > }
  > print(s10(1, 2, 3, 4, 5, 6, 7, 8, 9, 10))
  > print(s10(10, 20, 30, 40, 50, 60, 70, 80, 90, 100))
  > SWIFT
  $ ./lab.exe --emit-asm a.swift | sed -n '/^Lmain_0:/,/bl	_s10/p' | tail -12
  	mov	x0, x23
  	ldr	x9, [sp, #24]
  	mov	x1, x9
  	mov	x2, x19
  	mov	x3, x25
  	mov	x4, x27
  	mov	x5, x26
  	mov	x6, x24
  	mov	x7, x21
  	str	x20, [sp, #0]
  	str	x22, [sp, #8]
  	bl	_s10

The call still fills x0-x7 first: eight `mov`s into the argument registers, then the two stores.

  $ ./lab.exe --emit-asm a.swift | sed -n '/^Lmain_0:/,/bl	_s10/p' | grep -E -c '	mov	x[0-7], ' || true
  8

A ten-argument call runs and matches swiftc.

  $ ./lab.exe build a.swift --native -o a && ./a
  55
  550
  $ swiftc -Onone a.swift -o a_sw && ./a_sw
  55
  550

The outgoing area is sized to the WIDEST call the function makes: a twelve-argument call
reserves four words, all four written before the `bl`.

  $ cat > w.swift <<'SWIFT'
  > func w12(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ g: Int, _ h: Int, _ p: Int, _ q: Int, _ r: Int, _ s: Int, _ t: Int) -> Int {
  >   return a*1 + b*2 + c*3 + d*4 + e*5 + g*6 + h*7 + p*8 + q*9 + r*10 + s*11 + t*12
  > }
  > print(w12(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1))
  > print(w12(2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
  > SWIFT
  $ ./lab.exe --emit-asm w.swift | sed -n '/^Lmain_0:/,/bl	_w12/p' | grep -E -c '	str	x[0-9]+, \[sp, #(0|8|16|24)\]' || true
  4
  $ ./lab.exe build w.swift --native -o w && ./w
  78
  38
  $ swiftc -Onone w.swift -o w_sw && ./w_sw
  78
  38

The outgoing area and the SPILL homes share the frame, and they must not share a byte. isel puts
value `v` at `[sp, #8*(outgoing + v)]` and register allocation has to spill `v` to the same
address — if it assumed a fixed base instead, a call wide enough to grow the outgoing area would
overwrite a spilled value with an argument. Fourteen arguments means six outgoing words, and a
spilled loop variable lives right where the older code put its second one.

  $ cat > wide.swift <<'SWIFT'
  > func w14(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ g: Int, _ h: Int, _ p: Int, _ q: Int, _ r: Int, _ s: Int, _ t: Int, _ u: Int, _ w: Int) -> Int {
  >   return a + b + c + d + e + g + h + p + q + r + s + t + u + w
  > }
  > var acc = 0
  > for i in 0 ..< 3 {
  >   acc = acc + w14(i, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13)
  > }
  > print(acc)
  > SWIFT
  $ ./lab.exe build wide.swift --native --regalloc=stack -o wide_s && ./wide_s
  276
  $ ./lab.exe build wide.swift --native --regalloc=linscan -o wide_l && ./wide_l
  276
  $ ./lab.exe build wide.swift --native --regalloc=graphcolor -o wide_g && ./wide_g
  276
  $ swiftc -Onone wide.swift -o wide_sw && ./wide_sw
  276
