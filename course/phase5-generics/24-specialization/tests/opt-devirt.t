DEVIRTUALIZATION — `TODO(24a)`, the fold loop in `devirt_module`, seen through `--sil-opt`.
Every fold here is licensed by one thing: `wrap_of` (given) walking the SSA def-chain and
PROVING what concrete type is inside an existential. With a proof in hand, a witness dispatch
becomes a direct call, an `open_existential` becomes an alias for the payload it was going to
copy out, and a `same_witness` becomes a constant that `simplify_cfg` then folds the branch on.
Without one, nothing moves. (`--sil-opt` runs the whole `-O` pipeline, so the specializer of
`TODO(24b)` is on this path too; these programs are written so that the devirt folds are what
the greps see.)

A dispatch on an existential built right there is provable, so it folds to a direct call — and
the second inline round then eats the call entirely, leaving `A.v`'s body inline in `main`:

  $ cat > d.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > let s: P = A(x: 21)
  > print(s.v())
  > EOF
  $ ./lab.exe --emit-sil d.swift | grep -c 'witness_method' || true
  1
  $ ./lab.exe --sil-opt d.swift | grep -c 'witness_method' || true
  0
  $ ./lab.exe --sil-opt d.swift | grep -c 'init_existential' || true
  0
  $ ./lab.exe --sil-opt d.swift | sed -n '/sil @main/,/^}/p'
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 21
    %1 = struct (%0) $A
    %13 = struct_extract %1, #0 $Int
    %7 = apply @print(%13)
    return
  }

An UNPROVABLE existential is left alone. `e` is assigned an `A` and then, on a path the
optimizer cannot rule out, a `B`: two possible tables reach the dispatch, so it stays dynamic.
This is the case that keeps the pass honest — both worlds coexist, exactly as in swiftc:

  $ cat > u.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > struct B: P { func v() -> Int { return 7 } }
  > func h(_ e: P) -> Int { return e.v() }
  > var e: P = A(x: 1)
  > if 1 < 2 { e = B() }
  > print(h(e))
  > EOF
  $ ./lab.exe --sil-opt u.swift | grep -c 'witness_method' || true
  1
  $ ./lab.exe build u.swift -O -o u && ./u
  7

A `same_witness` over a proven wrap is a constant, and `simplify_cfg` then deletes the branch
that can no longer be taken. Here `p` is provably an `A`: the `as? A` keeps only its `.some`
side and the `as? B` keeps only its `.none` side — no identity test survives, and neither does
the `open_existential` the successful branch would have used:

  $ cat > c.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > struct B: P { func v() -> Int { return 7 } }
  > let p: P = A(x: 5)
  > if let a = p as? A { print(a.x) } else { print(-1) }
  > if let b = p as? B { print(b.v()) } else { print(-2) }
  > EOF
  $ ./lab.exe --emit-sil c.swift | grep -c 'same_witness' || true
  2
  $ ./lab.exe --sil-opt c.swift | grep -c 'same_witness' || true
  0
  $ ./lab.exe --sil-opt c.swift | grep -c 'open_existential' || true
  0
  $ ./lab.exe --sil-opt c.swift | grep 'enum #'
    %9 = enum #1 (%1) $A?
    %32 = enum #0 () $B?
  $ ./lab.exe build c.swift -O -o c && ./c
  5
  -2

A cast whose answer genuinely changes from iteration to iteration is NOT provable, so the
identity test survives and the program still answers correctly:

  $ cat > l.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > struct B: P { func v() -> Int { return 2 } }
  > var total = 0
  > var p: P = A()
  > for i in 0 ..< 6 {
  >   if let _ = p as? A { total = total + 10 } else { total = total + 1 }
  >   if i % 2 == 0 { p = B() } else { p = A() }
  > }
  > print(total)
  > EOF
  $ ./lab.exe --sil-opt l.swift | grep -c 'same_witness' || true
  1
  $ ./lab.exe build l.swift -O -o l && ./l
  33
