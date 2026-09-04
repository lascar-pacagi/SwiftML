TODO(26c) — `rt.release`, in `irgen.ml`: the six-line runtime function the whole phase rests on.
Decrement; if the count reached zero, run vtable slot 0 (the deinit bodies), then slot 1 (the
field releases), then free — once. Everything below needs the other two holes as well; what
this file observes is the emitted runtime and, finally, WHEN a `deinit` prints.

The function itself: a decrement, a zero test, the two indirect calls in slot order, and one
`free`. `rt.retain` above it is the shape to mirror.

  $ cat > s.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func f() { let a = T(1)
  >   print(a.id) }
  > f()
  > SWIFT
  $ ./lab.exe --emit-llvm s.swift | sed -n '/define private void @rt.release/,/^}/p'
  define private void @rt.release(ptr %o) {
    %rcp = getelementptr i8, ptr %o, i64 8
    %rc = load i64, ptr %rcp
    %n = sub i64 %rc, 1
    store i64 %n, ptr %rcp
    %z = icmp eq i64 %n, 0
    br i1 %z, label %dead, label %done
  dead:
    %vt = load ptr, ptr %o
    %dtor = load ptr, ptr %vt
    call void %dtor(ptr %o)
    %dsp = getelementptr ptr, ptr %vt, i64 1
    %dstr = load ptr, ptr %dsp
    call void %dstr(ptr %o)
    call void @free(ptr %o)
    br label %done
  done:
    ret void
  }

Scope exit, in REVERSE declaration order, and a shared object released exactly once — `c` is a
second name for `a`'s object, so only two deinits fire, not three:

  $ cat > scope.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func f() {
  >   let a = T(1)
  >   let b = T(2)
  >   let c = a
  >   print(a.id + b.id + c.id)
  > }
  > f()
  > print(9)
  > SWIFT
  $ ./lab.exe build scope.swift -o scope && ./scope
  4
  2
  1
  9

Reassignment builds the new object BEFORE releasing the old one; and a top-level `var` never
deinits at all, because it is a global and swiftc runs no deinit at process exit:

  $ cat > re.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i
  >     print(id * 10) }
  >   deinit { print(id * 10 + 1) }
  > }
  > var v = T(2)
  > v = T(3)
  > print(300)
  > SWIFT
  $ ./lab.exe build re.swift -o re && ./re
  20
  30
  21
  300

The deallocation ORDER, which is the whole reason there are two chains: ALL the deinit bodies
run derived to base FIRST (2000 then 1003), and only THEN the fields release (7). The
plausible per-level order — 2000, 7, 1003 — is what swiftc does NOT do.

  $ cat > chain.swift <<'SWIFT'
  > class Leaf {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > class A {
  >   var x: Int
  >   init(_ v: Int) { x = v }
  >   deinit { print(1000 + x) }
  > }
  > class B: A {
  >   var l: Leaf
  >   init(_ v: Int, _ l0: Leaf) { l = l0
  >     super.init(v) }
  >   deinit { print(2000) }
  > }
  > func go() {
  >   let b = B(3, Leaf(7))
  >   print(b.x)
  > }
  > go()
  > print(0)
  > SWIFT
  $ ./lab.exe build chain.swift -o chain && ./chain
  3
  2000
  1003
  7
  0

Ownership transfers through a return, loop iterations release their own locals, and a statement
temporary dies at the end of its statement — the same at `-Onone` and at `-O`, because
retain/release are SIDE-EFFECTING and no pass may drop or reorder them:

  $ cat > own.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func mk() -> T { let t = T(6)
  >   return t }
  > func g() {
  >   let t = mk()
  >   print(t.id * 2)
  > }
  > g()
  > for i in 0 ..< 2 {
  >   let t = T(i + 10)
  >   print(t.id * 100)
  > }
  > print(T(4).id)
  > print(5)
  > SWIFT
  $ ./lab.exe build own.swift -o own && ./own
  12
  6
  1000
  10
  1100
  11
  4
  4
  5
  $ ./lab.exe build own.swift -O -o ownO && ./ownO
  12
  6
  1000
  10
  1100
  11
  4
  4
  5

`break` and `continue` release the locals of the iteration they abandon, not just the ones a
normal fall-through would:

  $ cat > brk.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func f() {
  >   var i = 0
  >   while i < 4 {
  >     let t = T(i)
  >     i = i + 1
  >     if t.id == 1 { continue }
  >     if t.id == 2 { break }
  >     print(t.id * 100)
  >   }
  >   print(9)
  > }
  > f()
  > SWIFT
  $ ./lab.exe build brk.swift -o brk && ./brk
  0
  0
  1
  2
  9

Replacing a class-typed FIELD releases what it held, and the object it held dies right there —
not at the end of the enclosing scope:

  $ cat > fld.swift <<'SWIFT'
  > class L {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > class Box {
  >   var l: L
  >   init(_ x: L) { l = x }
  >   func put(_ x: L) { l = x }
  > }
  > func f() {
  >   let b = Box(L(1))
  >   b.put(L(2))
  >   print(50)
  > }
  > f()
  > print(9)
  > SWIFT
  $ ./lab.exe build fld.swift -o fld && ./fld
  1
  50
  2
  9
