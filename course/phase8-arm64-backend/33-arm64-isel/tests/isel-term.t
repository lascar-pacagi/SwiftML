TODO(33b) — `sel_term`: the block terminators. `return` is reachable with this hole alone (an
empty program is a `main` that only returns); the branch cases also need `sel_instr`, because a
condition is a value. Programs are built `--native` and RUN — the native binary is the point.

An empty program is a `main` that sets up its frame, returns 0 and exits 0. The prologue pushes
the frame record first (`stp` at offset 0), then carves the locals; the epilogue mirrors it:

  $ : > empty.swift
  $ ./lab.exe --emit-asm empty.swift | sed -n '/^_main:/,/\tret/p'
  _main:
  	sub	sp, sp, #16
  	stp	x29, x30, [sp, #0]
  	mov	x29, sp
  	sub	sp, sp, #32
  Lmain_0:
  	mov	x0, #0
  	add	sp, sp, #32
  	ldp	x29, x30, [sp, #0]
  	add	sp, sp, #16
  	ret
  $ ./lab.exe build empty.swift --native -o empty && ./empty; echo "exit=$?"
  exit=0

`func one() -> Int { return 1 }` loads the value into x0 right before the epilogue:

  $ cat > one.swift <<'EOF'
  > func one() -> Int {
  >   return 1
  > }
  > print(one())
  > EOF
  $ ./lab.exe --emit-asm one.swift | sed -n '/^Lone_0:/,/\tret/p'
  Lone_0:
  	mov	x9, #1
  	str	x9, [sp, #16]
  	ldr	x0, [sp, #16]
  	add	sp, sp, #32
  	ldp	x29, x30, [sp, #0]
  	add	sp, sp, #16
  	ret
  $ ./lab.exe build one.swift --native -o one && ./one
  1

An `if` is `cmp #0` + `b.ne` to the then-block + `b` to the else-block; both branches join with a
plain `b`, and the taken side prints:

  $ cat > if.swift <<'EOF'
  > let n = 7
  > if n > 5 {
  >   print(1)
  > } else {
  >   print(2)
  > }
  > print(3)
  > EOF
  $ ./lab.exe --emit-asm if.swift | grep -E '\tcmp\tx9, #0|\tb(\.ne)?\t|^L'
  Lmain_0:
  	cmp	x9, #0
  	b.ne	Lmain_1
  	b	Lmain_3
  Lmain_1:
  	b	Lmain_2
  Lmain_2:
  Lmain_3:
  	b	Lmain_2
  Lfmt_int:
  $ ./lab.exe build if.swift --native -o if && ./if
  1
  3

A `while` loop's header block is entered once and re-entered by the back-edge — two `b Lmain_1`
— and the native run counts to 3:

  $ cat > while.swift <<'EOF'
  > var i = 0
  > while i < 3 {
  >   i = i + 1
  > }
  > print(i)
  > EOF
  $ ./lab.exe --emit-asm while.swift | grep -E -c '\tb\tLmain_1$' || true
  2
  $ ./lab.exe build while.swift --native -o while && ./while
  3

`for` with `break` and `continue` (the latch block from concept 09): 0 1 2 4, then 10:

  $ cat > for.swift <<'EOF'
  > for i in 0 ..< 10 {
  >   if i == 3 { continue }
  >   if i == 5 { break }
  >   print(i)
  > }
  > var k = 0
  > for j in 0 ..< 5 { k = k + j }
  > print(k)
  > EOF
  $ ./lab.exe build for.swift --native -o for && ./for
  0
  1
  2
  4
  10

A `trap` terminator is `brk #1` (a force-unwrap of nil; optionals themselves are outside v0, so
the enum ops around it are UNSUPPORTED comments):

  $ cat > trap.swift <<'EOF'
  > let x: Int? = nil
  > print(x!)
  > EOF
  $ ./lab.exe --emit-asm trap.swift | grep -c '\tbrk\t#1' || true
  1

Recursion needs nothing special — `fib` is a `bl _fib` from inside `_fib`; the native `fib(20)`
is 6765:

  $ cat > fib.swift <<'EOF'
  > func fib(_ n: Int) -> Int {
  >   if n < 2 { return n }
  >   return fib(n - 1) + fib(n - 2)
  > }
  > print(fib(20))
  > EOF
  $ ./lab.exe --emit-asm fib.swift | sed -n '/^_fib:/,/^_main:/p' | grep -c '\tbl\t_fib' || true
  2
  $ ./lab.exe build fib.swift --native -o fib && ./fib
  6765

A 40-statement `main` has ~130 values: the frame is over 1 KB and still assembles, because
the frame record is pushed at offset 0 (a `stp …, [sp, #FRAME-16]` overflows stp's range at
504 bytes — `as` refused such files until this was fixed):

  $ { echo 'var s = 0'; i=0; while [ $i -lt 40 ]; do echo "s = s + $i"; i=$((i+1)); done; echo 'print(s)'; } > wide.swift
  $ ./lab.exe --emit-asm wide.swift | sed -n '/^_main:/,/^Lmain_0:/p'
  _main:
  	sub	sp, sp, #16
  	stp	x29, x30, [sp, #0]
  	mov	x29, sp
  	sub	sp, sp, #1344
  Lmain_0:
  $ ./lab.exe build wide.swift --native -o wide && ./wide
  780

Backend B agrees with Backend A (the LLVM path) on the same program — two backends, one front end:

  $ ./lab.exe build fib.swift -o fib_llvm && ./fib_llvm > out_llvm && ./fib > out_native
  $ cmp out_llvm out_native && echo SAME
  SAME
