TODO(29a) — the closure lifting, in `silgen.ml`. A closure literal becomes two things: a
top-level function whose extra first parameter is the context, and a `closure` value pairing
that function with a heap record of the captured values. `--emit-sil` stops before IRGen, so
every case here reads the lifting alone.

`makeAdder` is the whole transformation in one program: the body lifts to `makeAdder$clo0`,
`n` is read out of the context with `capture_get`, and the call goes through the pair.

  $ cat > mk.swift <<'SWIFT'
  > func makeAdder(_ n: Int) -> (Int) -> Int {
  >   return { (x: Int) -> Int in x + n }
  > }
  > let a = makeAdder(7)
  > print(a(1))
  > SWIFT
  $ ./lab.exe --emit-sil mk.swift | sed -n '/sil @makeAdder\$clo0/,/^}/p'
  sil @makeAdder$clo0(%0 : $$ctx, %1 : $Int) -> $Int {
  bb0:
    %2 = alloc_stack $Int  // x
    store %1 to %2
    %4 = capture_get %0, #0 $Int
    %5 = load %2 $Int
    %6 = binop "+" %5, %4 $Int
    return %6
  }

The lifted function's parameter 0 is the context and the captured value is copied in AT the
closure expression, not read later — `closure @makeAdder$clo0 (%3)` names the value it stored:

  $ ./lab.exe --emit-sil mk.swift | grep 'closure @'
    %4 = closure @makeAdder$clo0 (%3) $(Int) -> Int

A capture-free literal still gets a context, an empty one — one calling convention, no special
case for "this closure happens to capture nothing":

  $ cat > free.swift <<'SWIFT'
  > let double = { (x: Int) -> Int in x * 2 }
  > print(double(21))
  > SWIFT
  $ ./lab.exe --emit-sil free.swift | grep 'closure @'
    %0 = closure @main$clo0 () $(Int) -> Int

Two literals in the same function get two lifted functions, numbered in source order:

  $ cat > two.swift <<'SWIFT'
  > func pair(_ n: Int) -> Int {
  >   let a = { (x: Int) -> Int in x + n }
  >   let b = { (x: Int) -> Int in x * n }
  >   return a(1) + b(2)
  > }
  > print(pair(3))
  > SWIFT
  $ ./lab.exe --emit-sil two.swift | grep -E '^sil @pair\$clo'
  sil @pair$clo0(%0 : $$ctx, %1 : $Int) -> $Int {
  sil @pair$clo1(%0 : $$ctx, %1 : $Int) -> $Int {

A struct capture is copied by VALUE, so the context slot has the struct's type:

  $ cat > st.swift <<'SWIFT'
  > struct P { var x: Int; var y: Int }
  > func scaler(_ p: P) -> (Int) -> Int {
  >   return { (k: Int) -> Int in p.x * k + p.y }
  > }
  > let f = scaler(P(x: 3, y: 1))
  > print(f(10))
  > SWIFT
  $ ./lab.exe --emit-sil st.swift | grep -E 'closure @|capture_get'
    %4 = closure @scaler$clo0 (%3) $(Int) -> Int
    %4 = capture_get %0, #0 $P

The closure value is a fresh +1 — it owns its heap context. The driver runs concept 27's
ownership verifier on every compile, so a lifting that forgets to mark the result owned does
not merely leak, it fails to compile: no output here is the pass.

  $ ./lab.exe --emit-sil mk.swift > /dev/null
