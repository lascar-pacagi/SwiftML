SPECIALIZATION — `TODO(24b)`, the call-site specializer in `specialize_module`, seen through
`--sil-opt`. Concept 22 compiled a generic ONCE with `T` erased to its constraint; this pass
un-does that where it can: prove the concrete type at every erased parameter of a call, clone
the callee for that type as `g$Sn`, retype the clone's parameters, pass the raw payloads instead
of existentials, and retarget the call. One unprovable position and the call stays on the erased
original — coexistence, exactly as swiftc does it. (`--sil-opt` runs the whole `-O` pipeline, so
the devirt folds of `TODO(24a)` are on this path too.)

One concrete type, one clone. The generic's parameter is retyped from `$any P` to `$A`, and the
call passes the struct itself — no wrap in sight:

  $ cat > one.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > func dbl<T: P>(_ t: T) -> Int { return t.v() + t.v() }
  > print(dbl(A(x: 10)))
  > EOF
  $ ./lab.exe --emit-sil one.swift | grep '^sil @dbl'
  sil @dbl(%0 : $any P) -> $Int {
  $ ./lab.exe --sil-opt one.swift | grep '^sil @dbl'
  sil @dbl$A(%0 : $A) -> $Int {
  $ ./lab.exe --sil-opt one.swift | grep -c 'init_existential' || true
  0
  $ ./lab.exe build one.swift -O -o one && ./one
  20

And this is the payoff — the CASCADE. Inside the clone, `t.v()` has a concrete receiver, so
devirt makes it a direct call, the second inline round splices `A.v`'s body in, and GVN merges
the two now-identical extracts. `dbl$A` ends as one `struct_extract` and one `binop`: the whole
protocol abstraction has been compiled away.

  $ ./lab.exe --sil-opt one.swift | sed -n '/sil @dbl\$A/,/^}/p'
  sil @dbl$A(%0 : $A) -> $Int {
  bb0:
    %14 = struct_extract %0, #0 $Int
    %7 = binop "+" %14, %14 $Int
    return %7
  }

Two concrete types get two clones, one per type — and a recursive generic specializes into a
SELF-recursive clone, because the recursive call inside `rep$A` now proves `A` as well. (The
erased `@rep` survives beside it: it still calls itself, so dead-function elimination cannot
see that nothing else does. `@g` and `@dbl`, which are not recursive, are removed.)

  $ cat > two.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > struct B: P { func v() -> Int { return 100 } }
  > func g<T: P>(_ t: T) -> Int { return t.v() * 2 }
  > func rep<T: P>(_ t: T, _ n: Int) -> Int {
  >   if n == 0 { return 0 }
  >   return t.v() + rep(t, n - 1)
  > }
  > print(g(A(x: 3)) + g(B()))
  > print(rep(A(x: 5), 4))
  > EOF
  $ ./lab.exe --sil-opt two.swift | grep -oE 'sil @(g|rep)\$[A-Z]' | sort
  sil @g$A
  sil @g$B
  sil @rep$A
  $ ./lab.exe --sil-opt two.swift | grep 'function_ref @rep'
    %16 = function_ref @rep
    %15 = function_ref @rep$A
    %16 = function_ref @rep$A
  $ ./lab.exe build two.swift -O -o two && ./two
  206
  20

A NON-generic function that happens to take `any P` is not a specialization candidate: there is
no type parameter to bind, so `@h` keeps its `$any P` signature and no `h$A` is ever created.
(The dispatch INSIDE it is a separate question, and one this program cannot answer either — see
the honest reading in §2.)

  $ cat > ng.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > func h(_ e: P) -> Int { return e.v() }
  > print(h(A(x: 2)))
  > EOF
  $ ./lab.exe --sil-opt ng.swift | grep '^sil @h'
  sil @h(%0 : $any P) -> $Int {
  $ ./lab.exe --sil-opt ng.swift | grep -c 'h\$A' || true
  0
  $ ./lab.exe build ng.swift -O -o ng && ./ng
  2

A generic calling a generic specializes in two steps: `outer$A` is cloned first, and inside it
the inner call now proves `A` too, so `inner$A` follows. The erased `@inner` stays in the module
for any caller that could not be proved:

  $ cat > gg.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > func inner<T: P>(_ t: T) -> Int { return t.v() }
  > func outer<T: P>(_ t: T) -> Int { return inner(t) + inner(t) }
  > print(outer(A(x: 3)))
  > EOF
  $ ./lab.exe --sil-opt gg.swift | grep -E '^sil @(inner|outer)' | sort
  sil @inner$A(%0 : $A) -> $Int {
  sil @inner(%0 : $any P) -> $Int {
  sil @outer$A(%0 : $A) -> $Int {
  $ ./lab.exe build gg.swift -O -o gg && ./gg
  6

A conformer too big for the 3-word buffer was HEAP-BOXED by concept 23. Specializing the call
removes the existential entirely, so the box goes with it — no `malloc` survives:

  $ cat > big.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct Big: P {
  >   var a: Int
  >   var b: Int
  >   var c: Int
  >   var d: Int
  >   var e: Int
  >   func v() -> Int { return a + b + c + d + e }
  > }
  > func dbl<T: P>(_ t: T) -> Int { return t.v() + t.v() }
  > print(dbl(Big(a: 1, b: 2, c: 3, d: 4, e: 5)))
  > EOF
  $ ./lab.exe --sil-opt big.swift | grep -c 'init_existential' || true
  0
  $ ./lab.exe build big.swift -O -o big && ./big
  30
  $ ./lab.exe --emit-llvm big.swift -O | grep -c 'call ptr @malloc' || true
  0
