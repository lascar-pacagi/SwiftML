TODO(26b) — the FIELD-DESTROY chain, in `silgen.ml`. Deallocation is TWO chains, not one, and
they run in OPPOSITE directions: every `deinit` BODY first, derived to base (`C.deinit`, vtable
slot 0), then every class-typed FIELD, base to derived (`C.destroy`, slot 1). You write the
second. `--emit-sil` shows both, so their shapes can be compared side by side.

The hierarchy: `A` holds an `Int`, `B: A` holds a `Leaf`, and both have a `deinit` body.

  $ cat > ch.swift <<'SWIFT'
  > class L {
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
  >   var l: L
  >   init(_ v: Int, _ l0: L) { l = l0
  >     super.init(v) }
  >   deinit { print(2000) }
  > }
  > print(1)
  > SWIFT

`B.deinit` runs its own body and only THEN chains up to `A.deinit` — derived before base — and
it releases nothing: bodies do not touch fields.

  $ ./lab.exe --emit-sil ch.swift | sed -n '/sil @B.deinit/,/^}/p' | grep -E 'apply @print|function_ref|release'
    %4 = apply @print(%3)
    %7 = function_ref @A.deinit

`B.destroy` is the mirror image: it chains to `A.destroy` FIRST, so the base's fields die before
the derived's, and only then releases `B`'s own `l`.

  $ ./lab.exe --emit-sil ch.swift | sed -n '/sil @B.destroy/,/^}/p' | grep -E 'function_ref|ref_element_addr|release'
    %5 = function_ref @A.destroy
    %7 = ref_element_addr %3, #1
    release %8

A class with no class-typed fields and no superclass has an empty `destroy` — the chain still
exists (the runtime always calls slot 1) but there is nothing in it:

  $ ./lab.exe --emit-sil ch.swift | sed -n '/sil @A.destroy/,/^}/p' | grep -cE 'release|function_ref' || true
  0

A field of a NON-class type is not released: releasing an `Int` would be a use-after-free of a
number. `A` holds only `x: Int`, so its destroy stays empty while `B`'s releases exactly one:

  $ ./lab.exe --emit-sil ch.swift | sed -n '/sil @B.destroy/,/^}/p' | grep -c 'release' || true
  1

Three levels deep, each `destroy` chains to its immediate superclass's — never past it — so the
whole base-to-derived order falls out of a two-line rule repeated at every level:

  $ cat > d3.swift <<'SWIFT'
  > class L { var id: Int
  >   init(_ i: Int) { id = i }
  >   deinit { print(id) } }
  > class A { var a: L
  >   init(_ x: L) { a = x } }
  > class B: A { var b: L
  >   init(_ x: L, _ y: L) { b = y
  >     super.init(x) } }
  > class C: B { var c: L
  >   init(_ x: L, _ y: L, _ z: L) { c = z
  >     super.init(x, y) } }
  > print(1)
  > SWIFT
  $ ./lab.exe --emit-sil d3.swift | sed -n '/sil @C.destroy/,/^}/p' | grep -E 'function_ref|release'
    %5 = function_ref @B.destroy
    release %8
  $ ./lab.exe --emit-sil d3.swift | sed -n '/sil @B.destroy/,/^}/p' | grep -E 'function_ref|release'
    %5 = function_ref @A.destroy
    release %8

Both chains are reachable ONLY through the vtable, and IRGen puts them in slots 0 and 1 of
every class's table, ahead of the methods — which is why the optimizer's dead-function removal
has to know about them (it does; §2). Nothing else in the module names `@B.destroy`:

  $ ./lab.exe --emit-llvm ch.swift | grep '^@vtbl'
  @vtbl.L = private unnamed_addr constant [2 x ptr] [ptr @L.deinit, ptr @L.destroy]
  @vtbl.A = private unnamed_addr constant [2 x ptr] [ptr @A.deinit, ptr @A.destroy]
  @vtbl.B = private unnamed_addr constant [2 x ptr] [ptr @B.deinit, ptr @B.destroy]
  $ ./lab.exe --emit-llvm ch.swift | grep -c 'call void @B.destroy' || true
  0
