Ownership SSA: ARC's rules made visible and statically checked. RED until TODO(27) — the
ownership verifier (the driver runs it on every compile).

The SIL now carries STRUCTURE instead of raw refcount ops — a borrow that becomes an owner is
a `copy_value`; storage dying is `load [take]` + `destroy_value`:

  $ cat > o.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  > }
  > func f() {
  >   let a = T(1)
  >   let c = a
  >   print(c.id)
  > }
  > f()
  > SWIFT
  $ ./lab.exe --emit-sil o.swift | grep -cE 'copy_value'
  1
  $ ./lab.exe --emit-sil o.swift | grep -cE 'load \[take\]'
  2
  $ ./lab.exe --emit-sil o.swift | grep -cE 'destroy_value'
  2

Guaranteed parameters never touch memory — `self` and class params are pure SSA values
(spilling one would make the entry store consume a borrow; the verifier enforces it):

  $ ./lab.exe --emit-sil o.swift | grep -A3 'sil @T.init'
  sil @T.init(%0 : $T, %1 : $Int) -> $() {
  bb0:
    %2 = alloc_stack $Int  // i
    store %1 to %2

Behavior is UNCHANGED by the recast — deinit order still matches swiftc, at -Onone and -O:

  $ cat > life.swift <<'SWIFT'
  > class T {
  >   var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) }
  > }
  > func g() {
  >   let a = T(1)
  >   let b = T(2)
  >   print(a.id + b.id)
  > }
  > g()
  > var v = T(4)
  > v = T(5)
  > print(9)
  > SWIFT
  $ ./lab.exe build life.swift -o life && ./life
  3
  2
  1
  4
  9
  $ ./lab.exe build life.swift -O -o lifeO && ./lifeO
  3
  2
  1
  4
  9
