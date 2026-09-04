The silgen hole, TODO(12): a `switch` becomes a DISPATCH CHAIN — read the discriminant once,
then a `tag == k` test per case, each arm in its own block, all of them branching to one merge
block. `--emit-sil` stops after SILGen, so this file is about the CFG you build, not about what
it prints; `run-switch.t` runs the same programs.

`switch s` on a three-case enum reads the tag once and tests it three times; the arms that name
a payload read it with `enum_payload` into a slot of its own. Two blocks end `unreachable` here:
bb1, the merge, because every arm left through a `return`, and bb7, where the chain runs out —
an exhaustive switch has no case left for it:

  $ cat > area.swift <<'EOF'
  > enum Shape {
  >   case circle(Int)
  >   case rect(Int, Int)
  >   case dot
  > }
  > func area(_ s: Shape) -> Int {
  >   switch s {
  >   case .circle(let r): return r * r
  >   case .rect(let w, let h): return w * h
  >   case .dot: return 0
  >   }
  > }
  > print(area(Shape.dot))
  > EOF
  $ ./lab.exe --emit-sil area.swift | sed -n '/sil @area/,/^}/p'
  sil @area(%0 : $Shape) -> $Int {
  bb0:
    %1 = alloc_stack $Shape  // s
    store %0 to %1
    %3 = load %1 $Shape
    %4 = enum_tag %3
    %5 = integer_literal $Int, 0
    %6 = binop "==" %4, %5 $Bool
    cond_br %6, bb2, bb3
  bb1:
    unreachable
  bb2:
    %7 = enum_payload %3, #0 $Int
    %8 = alloc_stack $Int  // r
    store %7 to %8
    %10 = load %8 $Int
    %11 = load %8 $Int
    %12 = binop "*" %10, %11 $Int
    return %12
  bb3:
    %13 = integer_literal $Int, 1
    %14 = binop "==" %4, %13 $Bool
    cond_br %14, bb4, bb5
  bb4:
    %15 = enum_payload %3, #0 $Int
    %16 = alloc_stack $Int  // w
    store %15 to %16
    %18 = enum_payload %3, #1 $Int
    %19 = alloc_stack $Int  // h
    store %18 to %19
    %21 = load %16 $Int
    %22 = load %19 $Int
    %23 = binop "*" %21, %22 $Int
    return %23
  bb5:
    %24 = integer_literal $Int, 2
    %25 = binop "==" %4, %24 $Bool
    cond_br %25, bb6, bb7
  bb6:
    %26 = integer_literal $Int, 0
    return %26
  bb7:
    unreachable
  }

The subject is evaluated ONCE — one `enum_tag`, however many cases the chain tests:

  $ ./lab.exe --emit-sil area.swift | grep -c enum_tag
  1

A two-value payload binds both, in order: `enum_payload %s, #0` and `#1`, each into its own slot:

  $ ./lab.exe --emit-sil area.swift | grep enum_payload
    %7 = enum_payload %3, #0 $Int
    %15 = enum_payload %3, #0 $Int
    %18 = enum_payload %3, #1 $Int

`case .a(_)` extracts nothing — an ignored binding is not read out of the payload at all:

  $ cat > ignore.swift <<'EOF'
  > enum E { case a(Int), b }
  > var t = 0
  > let e = E.a(5)
  > switch e {
  > case .a(_): t = 1
  > case .b: t = 2
  > }
  > print(t)
  > EOF
  $ ./lab.exe --emit-sil ignore.swift | grep -cE 'enum_payload' || true
  0

Used as a STATEMENT, the arms fall through to the merge block instead of returning — the
`br bb1`s are the join, and the last `cond_br`'s false side is `unreachable` (the switch is
exhaustive, so no case is left):

  $ ./lab.exe --emit-sil ignore.swift | sed -n '/sil @main/,/^}/p'
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 0
    %1 = alloc_stack $Int  // t
    store %0 to %1
    %3 = integer_literal $Int, 5
    %4 = enum #0 (%3) $E
    %5 = alloc_stack $E  // e
    store %4 to %5
    %7 = load %5 $E
    %8 = enum_tag %7
    %9 = integer_literal $Int, 0
    %10 = binop "==" %8, %9 $Bool
    cond_br %10, bb2, bb3
  bb1:
    %17 = load %1 $Int
    %18 = apply @print(%17)
    return
  bb2:
    %11 = integer_literal $Int, 1
    store %11 to %1
    br bb1
  bb3:
    %13 = integer_literal $Int, 1
    %14 = binop "==" %8, %13 $Bool
    cond_br %14, bb4, bb5
  bb4:
    %15 = integer_literal $Int, 2
    store %15 to %1
    br bb1
  bb5:
    unreachable
  }

An Int switch tests the VALUE, with no `enum_tag` in sight, and its `default` is the last
block in the chain — reached when every test has failed:

  $ cat > ints.swift <<'EOF'
  > let n = 2
  > switch n {
  > case 1: print(10)
  > case 2: print(20)
  > default: print(0)
  > }
  > print(99)
  > EOF
  $ ./lab.exe --emit-sil ints.swift | sed -n '/sil @main/,/^}/p'
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 2
    %1 = alloc_stack $Int  // n
    store %0 to %1
    %3 = load %1 $Int
    %4 = integer_literal $Int, 1
    %5 = binop "==" %3, %4 $Bool
    cond_br %5, bb2, bb3
  bb1:
    %14 = integer_literal $Int, 99
    %15 = apply @print(%14)
    return
  bb2:
    %6 = integer_literal $Int, 10
    %7 = apply @print(%6)
    br bb1
  bb3:
    %8 = integer_literal $Int, 2
    %9 = binop "==" %3, %8 $Bool
    cond_br %9, bb4, bb5
  bb4:
    %10 = integer_literal $Int, 20
    %11 = apply @print(%10)
    br bb1
  bb5:
    %12 = integer_literal $Int, 0
    %13 = apply @print(%12)
    br bb1
  }

A `default` on an enum switch takes the place of the `unreachable`: with one case tested, the
chain has one `cond_br` and the fallthrough block runs the default body:

  $ cat > deflt.swift <<'EOF'
  > enum E { case a, b, c }
  > let e = E.b
  > switch e {
  > case .a: print(1)
  > default: print(0)
  > }
  > EOF
  $ ./lab.exe --emit-sil deflt.swift | grep -E 'cond_br|unreachable|^bb'
  bb0:
    cond_br %6, bb2, bb3
  bb1:
  bb2:
  bb3:
