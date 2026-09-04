TODO(26a) — `take_ownership`, in `silgen.ml`: the one rule every durable store goes through.
A fresh +1 temp is CONSUMED (it stops being the statement's to release); anything else is
BORROWED and must be RETAINED. `--emit-sil` shows the traffic without needing the other holes.

A fresh object stored into a `let` needs no retain at all — the constructor already handed the
slot a +1 — and one release at scope exit balances it:

  $ cat > fresh.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func f() {
  >   let a = T(1)
  >   print(a.id)
  > }
  > f()
  > SWIFT
  $ ./lab.exe --emit-sil fresh.swift | sed -n '/sil @f/,/^}/p' | grep -cE '^  retain' || true
  0
  $ ./lab.exe --emit-sil fresh.swift | sed -n '/sil @f/,/^}/p' | grep -cE '^  release' || true
  1

A second binding to the SAME object is a borrow, so it retains — and now two releases fire, in
reverse declaration order, which is what makes the object die exactly once:

  $ cat > borrow.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func f() {
  >   let a = T(1)
  >   let b = a
  >   print(a.id + b.id)
  > }
  > f()
  > SWIFT
  $ ./lab.exe --emit-sil borrow.swift | sed -n '/sil @f/,/^}/p' | grep -E '^  (retain|release|store|return)'
    store %0 to %4
    retain %6
    store %6 to %8
    release %18
    release %20
    return

Reassignment evaluates the NEW object first and releases the OLD one after the store — get
that order backwards and `v = v` frees the object it is about to keep:

  $ cat > re.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func f() {
  >   var v = T(2)
  >   v = T(3)
  >   print(v.id)
  > }
  > f()
  > SWIFT
  $ ./lab.exe --emit-sil re.swift | sed -n '/sil @f/,/^}/p' | grep -E '^  (alloc_ref|store %|release)'
    store %0 to %4
    store %6 to %4
    release %10
    release %17

An ARGUMENT is GUARANTEED — borrowed for the length of the call, so the callee neither retains
nor releases it. `use` below has no ARC traffic in it whatsoever:

  $ cat > arg.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func use(_ t: T) -> Int { return t.id }
  > func f() { let a = T(1)
  >   print(use(a)) }
  > f()
  > SWIFT
  $ ./lab.exe --emit-sil arg.swift | sed -n '/sil @use/,/^}/p' | grep -cE '^  (retain|release)' || true
  0

A RETURN is the opposite: the caller receives +1, so the returned local is retained before the
scope releases it, and the caller's own binding then consumes that +1 with no retain of its own:

  $ cat > ret.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func mk() -> T { let t = T(6)
  >   return t }
  > func g() { let t = mk()
  >   print(t.id) }
  > g()
  > SWIFT
  $ ./lab.exe --emit-sil ret.swift | sed -n '/sil @mk/,/^}/p' | grep -E '^  (retain|release|return)'
    retain %6
    release %8
    return %6
  $ ./lab.exe --emit-sil ret.swift | sed -n '/sil @g/,/^}/p' | grep -cE '^  retain' || true
  0

A statement TEMPORARY nobody stored is released at the end of the statement, not at scope exit
— `T(4).id` builds an object, reads a field and drops it, all inside one line:

  $ cat > tmp.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func f() { print(T(4).id)
  >   print(5) }
  > f()
  > SWIFT
  $ ./lab.exe --emit-sil tmp.swift | sed -n '/sil @f/,/^}/p' | grep -E 'apply @print|release'
    %6 = apply @print(%5)
    release %0
    %9 = apply @print(%8)

A class-typed FIELD is durable too: writing one takes ownership of the new object and releases
what the field held — except during `init`, where there is nothing to release yet:

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
  > func f() { let b = Box(L(1))
  >   b.put(L(2))
  >   print(3) }
  > f()
  > SWIFT
  $ ./lab.exe --emit-sil fld.swift | sed -n '/sil @Box.init/,/^}/p' | grep -cE '^  release' || true
  0
  $ ./lab.exe --emit-sil fld.swift | sed -n '/sil @Box.put/,/^}/p' | grep -E '^  (retain|release)'
    retain %6
    release %10
