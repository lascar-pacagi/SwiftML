TODO(33a) — `sel_instr`: one ARM64 template per SIL instruction (the stack machine). Each case
reads the `--emit-asm` text of a small program. A function cannot be printed without its `ret`,
so this file needs `sel_term`'s `return` arm too: it stays `TODO` until both holes exist, then
every case here is about `sel_instr`. `oracle.t` runs the same programs natively.

`print(7)`: the literal is one `mov`, stored to its slot, reloaded, parked at `[sp, #0]` (Apple's
variadic-on-the-stack rule), and printf's format string is addressed with adrp/add:

  $ cat > lit.swift <<'EOF'
  > print(7)
  > EOF
  $ ./lab.exe --emit-asm lit.swift | sed -n '/^Lmain_0:/,/bl\t_printf/p'
  Lmain_0:
  	mov	x9, #7
  	str	x9, [sp, #16]
  	ldr	x9, [sp, #16]
  	str	x9, [sp, #0]
  	adrp	x0, Lfmt_int@PAGE
  	add	x0, x0, Lfmt_int@PAGEOFF
  	bl	_printf

`print(4611686018427387903)` (2^62 - 1) is built 16 bits at a time: `movz` then three `movk`:

  $ cat > big.swift <<'EOF'
  > print(4611686018427387903)
  > EOF
  $ ./lab.exe --emit-asm big.swift | grep -E '\tmov[zk]\t'
  	movz	x9, #65535, lsl #0
  	movk	x9, #65535, lsl #16
  	movk	x9, #65535, lsl #32
  	movk	x9, #16383, lsl #48

`let x = 5; print(x)`: `alloc_stack` is only a comment — the slot IS the variable — and the
`store`/`load` pair moves the value through x9:

  $ cat > var.swift <<'EOF'
  > let x = 5
  > print(x)
  > EOF
  $ ./lab.exe --emit-asm var.swift | sed -n '/^Lmain_0:/,/bl\t_printf/p'
  Lmain_0:
  	mov	x9, #5
  	str	x9, [sp, #16]
  	; alloc_stack x
  	ldr	x9, [sp, #16]
  	str	x9, [sp, #24]
  	ldr	x9, [sp, #24]
  	str	x9, [sp, #40]
  	ldr	x9, [sp, #40]
  	str	x9, [sp, #0]
  	adrp	x0, Lfmt_int@PAGE
  	add	x0, x0, Lfmt_int@PAGEOFF
  	bl	_printf

`a + b`, `a - b`, `a * b`, `a / b`, `-a`: each binop is load-load-compute-store on x9/x10,
`neg` is load-neg-store (counting only the x9 forms — the prologue's `sub sp` is not one):

  $ cat > ops.swift <<'EOF'
  > let a = 9
  > let b = 4
  > print(a + b)
  > print(a - b)
  > print(a * b)
  > print(a / b)
  > print(-a)
  > EOF
  $ ./lab.exe --emit-asm ops.swift | grep -E -c '\tadd\tx9, x9, x10' || true
  1
  $ ./lab.exe --emit-asm ops.swift | grep -E -c '\tsub\tx9, x9, x10' || true
  1
  $ ./lab.exe --emit-asm ops.swift | grep -E -c '\tmul\tx9, x9, x10' || true
  1
  $ ./lab.exe --emit-asm ops.swift | grep -E -c '\tsdiv\tx9, x9, x10' || true
  1
  $ ./lab.exe --emit-asm ops.swift | grep -E -c '\tneg\tx9, x9' || true
  1

`17 % 5`: ARM64 has no modulo, so it is the quotient by `sdiv` into x11 then `msub` for the
remainder (x9 - x11*x10):

  $ cat > mod.swift <<'EOF'
  > print(17 % 5)
  > EOF
  $ ./lab.exe --emit-asm mod.swift | grep -E -A1 '\tsdiv\t'
  	sdiv	x11, x9, x10
  	msub	x9, x11, x10, x9

The six comparisons are `cmp` + `cset` with the matching condition code, in source order:

  $ cat > cmp.swift <<'EOF'
  > let a = 3
  > let b = 2
  > print(a == b)
  > print(a != b)
  > print(a < b)
  > print(a <= b)
  > print(a > b)
  > print(a >= b)
  > EOF
  $ ./lab.exe --emit-asm cmp.swift | grep -E -c '\tcmp\tx9, x10' || true
  6
  $ ./lab.exe --emit-asm cmp.swift | grep -E '\tcset\t'
  	cset	x9, eq
  	cset	x9, ne
  	cset	x9, lt
  	cset	x9, le
  	cset	x9, gt
  	cset	x9, ge

`print(true)` picks "true"/"false" with a `csel` on the value and prints through `%s`; the
literal `true` is the integer 1:

  $ cat > bool.swift <<'EOF'
  > print(true)
  > EOF
  $ ./lab.exe --emit-asm bool.swift | sed -n '/^Lmain_0:/,/bl\t_printf/p'
  Lmain_0:
  	mov	x9, #1
  	str	x9, [sp, #16]
  	ldr	x9, [sp, #16]
  	adrp	x11, Ltrue@PAGE
  	add	x11, x11, Ltrue@PAGEOFF
  	adrp	x12, Lfalse@PAGE
  	add	x12, x12, Lfalse@PAGEOFF
  	cmp	x9, #0
  	csel	x9, x11, x12, ne
  	str	x9, [sp, #0]
  	adrp	x0, Lfmt_str@PAGE
  	add	x0, x0, Lfmt_str@PAGEOFF
  	bl	_printf
  $ ./lab.exe --emit-asm bool.swift | sed -n '/__cstring/,$p'
  	.section	__TEXT,__cstring,cstring_literals
  Lfmt_str:
  	.asciz	"%s\012"
  Lfalse:
  	.asciz	"false"
  Ltrue:
  	.asciz	"true"

A call loads its arguments into x0, x1 (in order), is a direct `bl _add`, and stores x0 as the
result; the callee spills x0/x1 to its parameters' slots on entry:

  $ cat > call.swift <<'EOF'
  > func add(_ a: Int, _ b: Int) -> Int {
  >   return a + b
  > }
  > print(add(1, 2))
  > EOF
  $ ./lab.exe --emit-asm call.swift | grep -E -B2 -A1 '\tbl\t_add'
  	ldr	x0, [sp, #16]
  	ldr	x1, [sp, #24]
  	bl	_add
  	str	x0, [sp, #40]
  $ ./lab.exe --emit-asm call.swift | sed -n '/^_add:/,/^Ladd_0:/p'
  _add:
  	sub	sp, sp, #16
  	stp	x29, x30, [sp, #0]
  	mov	x29, sp
  	sub	sp, sp, #96
  	str	x0, [sp, #16]
  	str	x1, [sp, #24]
  Ladd_0:

Eight arguments fill x0 through x7 — the whole AAPCS64 register set (more than eight is
concept 35):

  $ cat > eight.swift <<'EOF'
  > func f(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ g: Int, _ h: Int, _ i: Int) -> Int {
  >   return a + b + c + d + e + g + h + i
  > }
  > print(f(1, 2, 3, 4, 5, 6, 7, 8))
  > EOF
  $ ./lab.exe --emit-asm eight.swift | grep -E -B8 '\tbl\t_f$' | grep -E -c '\tldr\tx[0-7],' || true
  8

A struct is outside v0's scope: its instructions become visible `; UNSUPPORTED` comments,
never silent wrong code (the scalar parts still lower):

  $ cat > st.swift <<'EOF'
  > struct P { var x: Int; var y: Int }
  > let p = P(x: 1, y: 2)
  > print(p.x)
  > EOF
  $ ./lab.exe --emit-asm st.swift | grep -c 'UNSUPPORTED' || true
  2
  $ ./lab.exe --emit-asm st.swift | grep 'UNSUPPORTED' | head -1
  	; UNSUPPORTED instr for %2: %2 = struct (%0, %1) $P
