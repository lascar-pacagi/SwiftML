The second silgen hole, TODO(11): a case that carries associated values, `Shape.rect(3, 4)`,
lowers to `enum #tag (%a, %b)` — the same instruction, now with the evaluated arguments as the
payload. `--emit-sil` stops after SILGen. No program here builds a payload-free case, so this
file can go green on its own.

`Shape.rect(3, 4)` evaluates both arguments first, then builds case #1 around them:

  $ cat > rect.swift <<'EOF'
  > enum Shape {
  >   case circle(Int)
  >   case rect(Int, Int)
  >   case dot
  > }
  > let s = Shape.rect(3, 4)
  > EOF
  $ ./lab.exe --emit-sil rect.swift
  enum Shape { circle(Int); rect(Int, Int); dot }
  
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 3
    %1 = integer_literal $Int, 4
    %2 = enum #1 (%0, %1) $Shape
    %3 = alloc_stack $Shape  // s
    store %2 to %3
    return
  }

A one-value case is the same shape with one payload operand — `circle(5)` is `enum #0 (%0)`:

  $ cat > circle.swift <<'EOF'
  > enum Shape {
  >   case circle(Int)
  >   case rect(Int, Int)
  >   case dot
  > }
  > let s = Shape.circle(5)
  > EOF
  $ ./lab.exe --emit-sil circle.swift | grep -E 'integer_literal|enum'
  enum Shape { circle(Int); rect(Int, Int); dot }
    %0 = integer_literal $Int, 5
    %1 = enum #0 (%0) $Shape

An associated value is an ARBITRARY expression: `circle(2 + 3)` computes it, then wraps it:

  $ cat > expr.swift <<'EOF'
  > enum Shape {
  >   case circle(Int)
  >   case rect(Int, Int)
  > }
  > let n = 2
  > let s = Shape.circle(n + 3)
  > EOF
  $ ./lab.exe --emit-sil expr.swift | grep -E 'binop|enum'
  enum Shape { circle(Int); rect(Int, Int) }
    %5 = binop "+" %3, %4 $Int
    %6 = enum #0 (%5) $Shape

The tag counts EVERY case, payload or not: `wide` is #2 even though #0 and #1 carry nothing:

  $ cat > tags.swift <<'EOF'
  > enum K {
  >   case none
  >   case one
  >   case wide(Int, Int)
  > }
  > let k = K.wide(7, 8)
  > EOF
  $ ./lab.exe --emit-sil tags.swift | grep enum
  enum K { none; one; wide(Int, Int) }
    %2 = enum #2 (%0, %1) $K

A payload case's value can be a call result, and it can be passed on to another function:

  $ cat > fn.swift <<'EOF'
  > enum Shape {
  >   case circle(Int)
  >   case rect(Int, Int)
  > }
  > func twice(_ n: Int) -> Int { return n * 2 }
  > func take(_ s: Shape) -> Bool { return true }
  > print(take(Shape.circle(twice(4))))
  > EOF
  $ ./lab.exe --emit-sil fn.swift | sed -n '/sil @main/,/^}/p'
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 4
    %1 = function_ref @twice
    %2 = apply %1(%0)
    %3 = enum #0 (%2) $Shape
    %4 = function_ref @take
    %5 = apply %4(%3)
    %6 = apply @print(%5)
    return
  }
