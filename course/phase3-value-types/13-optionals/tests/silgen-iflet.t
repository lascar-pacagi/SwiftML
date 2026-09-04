The fourth silgen hole, TODO(13): `if let x = opt`. It is an `if` whose condition is the tag
test and whose then-block OPENS by binding `x` to the payload — compare it with the `if` and the
`switch` lowerings you already have. `--emit-sil` stops after SILGen. It needs the wrap hole; it
uses neither `!` nor `??`.

`if let v = a { print(v) }` tests the tag, and the taken block reads the payload into `v`'s own
slot before the body runs:

  $ cat > iflet.swift <<'EOF'
  > let a: Int? = 5
  > if let v = a { print(v) }
  > EOF
  $ ./lab.exe --emit-sil iflet.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 5
    %1 = enum #1 (%0) $Int?
    %2 = alloc_stack $Int?  // a
    store %1 to %2
    %4 = load %2 $Int?
    %5 = enum_tag %4
    %6 = integer_literal $Int, 1
    %7 = binop "==" %5, %6 $Bool
    cond_br %7, bb1, bb2
  bb1:
    %8 = enum_payload %4, #0 $Int
    %9 = alloc_stack $Int  // v
    store %8 to %9
    %11 = load %9 $Int
    %12 = apply @print(%11)
    br bb2
  bb2:
    return
  }

With an `else`, the two arms join at one merge block — the same diamond `if` builds:

  $ cat > else.swift <<'EOF'
  > let a: Int? = nil
  > if let v = a { print(v) } else { print(0) }
  > EOF
  $ ./lab.exe --emit-sil else.swift | grep -E '^bb|cond_br|br |enum_payload|apply'
  bb0:
    cond_br %6, bb1, bb3
  bb1:
    %7 = enum_payload %3, #0 $Int
    %11 = apply @print(%10)
    br bb2
  bb2:
  bb3:
    %13 = apply @print(%12)
    br bb2

`v` gets a slot of its OWN — `alloc_stack $Int  // v`, emitted in bb1 right after the payload
read, not beside `a`'s slot in bb0 — which is what scopes it to the arm:

  $ ./lab.exe --emit-sil else.swift | grep -E '^bb|alloc_stack'
  bb0:
    %1 = alloc_stack $Int?  // a
  bb1:
    %8 = alloc_stack $Int  // v
  bb2:
  bb3:

`if let` on a call result unwraps the call's value, once:

  $ cat > call.swift <<'EOF'
  > func f(_ n: Int) -> Int? {
  >   if n < 0 { return nil }
  >   return n * 2
  > }
  > if let r = f(5) { print(r) }
  > EOF
  $ ./lab.exe --emit-sil call.swift | sed -n '/sil @main/,/^}/p'
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 5
    %1 = function_ref @f
    %2 = apply %1(%0)
    %3 = enum_tag %2
    %4 = integer_literal $Int, 1
    %5 = binop "==" %3, %4 $Bool
    cond_br %5, bb1, bb2
  bb1:
    %6 = enum_payload %2, #0 $Int
    %7 = alloc_stack $Int  // r
    store %6 to %7
    %9 = load %7 $Int
    %10 = apply @print(%9)
    br bb2
  bb2:
    return
  }

An `if let` inside a loop puts its whole diamond in the loop BODY — the tag test is a block
the back edge returns to, not something hoisted out:

  $ cat > loop.swift <<'EOF'
  > func f(_ n: Int) -> Int? {
  >   if n % 2 == 0 { return n }
  >   return nil
  > }
  > var i = 0
  > var s = 0
  > while i < 4 {
  >   if let v = f(i) { s = s + v }
  >   i = i + 1
  > }
  > print(s)
  > EOF
  $ ./lab.exe --emit-sil loop.swift | sed -n '/sil @main/,/^}/p' | grep -E '^bb|enum_tag|cond_br|br bb'
  bb0:
    br bb1
  bb1:
    cond_br %8, bb2, bb3
  bb2:
    %12 = enum_tag %11
    cond_br %14, bb4, bb5
  bb3:
  bb4:
    br bb5
  bb5:
    br bb1
