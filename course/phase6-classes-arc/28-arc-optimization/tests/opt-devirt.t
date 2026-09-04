Whole-module class devirtualization is GIVEN code, in `devirt_module`. It is here because it is
the other half of Milestone M6 — copy propagation removes the ARC traffic a class costs, this
removes the DISPATCH — and because it is green from the first run: none of these programs makes
a `copy_value`, so `TODO(28)` never fires on them and `--sil-opt` works on the untouched
skeleton.

The rule is a proof, not a guess: if the receiver's STATIC class has no subclass anywhere in the
module, the vtable has exactly one possible answer, so the dispatch becomes a direct call — and
the inliner then eats it. `Solo` has no subclass and `solo(Solo())` ends as a single `load`;
`A` has `B`, so `go`'s dispatch stays dynamic:

  $ cat > sub.swift <<'SWIFT'
  > class A { var x: Int
  >   init() { x = 1 }
  >   func f() -> Int { return 1 } }
  > class B: A { override func f() -> Int { return 2 } }
  > class Solo { var y: Int
  >   init() { y = 5 }
  >   func g() -> Int { return y } }
  > func go(_ a: A) -> Int { return a.f() }
  > func solo(_ s: Solo) -> Int { return s.g() }
  > print(go(B()))
  > print(solo(Solo()))
  > SWIFT
  $ ./lab.exe --emit-sil sub.swift | grep -c 'class_method' || true
  2
  $ ./lab.exe --sil-opt sub.swift | grep -c 'class_method' || true
  1

The one that survives is `A`'s, inside `@go` — the overridden hierarchy is untouched, which is
the safety half of the pass:

  $ ./lab.exe --sil-opt sub.swift | grep -E '^sil @|class_method' | grep -B1 'class_method'
  sil @go(%0 : $A) -> $Int {
    %1 = class_method %0, #0 ; apply() $Int

And it still answers correctly, at `-Onone` and at `-O`: `B`'s override wins through an
`A`-typed parameter, and the devirtualized `Solo` gives the same 5:

  $ ./lab.exe build sub.swift -o sub && ./sub
  2
  5
  $ ./lab.exe build sub.swift -O -o subO && ./subO
  2
  5

Add a subclass and the SAME class stops being devirtualizable — the proof is a property of the
whole module, which is exactly why this is called whole-module optimization:

  $ cat > grown.swift <<'SWIFT'
  > class Solo { var y: Int
  >   init() { y = 5 }
  >   func g() -> Int { return y } }
  > class Grown: Solo { override func g() -> Int { return y * 2 } }
  > func solo(_ s: Solo) -> Int { return s.g() }
  > print(solo(Solo()))
  > print(solo(Grown()))
  > SWIFT
  $ ./lab.exe --sil-opt grown.swift | grep -c 'class_method' || true
  1
  $ ./lab.exe build grown.swift -O -o grown && ./grown
  5
  10

A subclass that adds a method but overrides NOTHING still blocks the proof for the parent's
methods, because our analysis is per-CLASS, not per-slot — an honest v0 imprecision (`final`,
and a per-slot version, are exercises):

  $ cat > wide.swift <<'SWIFT'
  > class P { var y: Int
  >   init() { y = 5 }
  >   func g() -> Int { return y } }
  > class Q: P { func extra() -> Int { return 1 } }
  > func use(_ p: P) -> Int { return p.g() }
  > print(use(P()))
  > print(use(Q()))
  > SWIFT
  $ ./lab.exe --sil-opt wide.swift | grep -c 'class_method' || true
  1
  $ ./lab.exe build wide.swift -O -o wide && ./wide
  5
  5
