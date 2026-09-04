The third silgen hole, TODO(13): `a ?? b`. Two paths produce ONE value, so — like a
value-producing `if` — it needs a slot both arms store into and one `load` after the merge.
`--emit-sil` stops after SILGen. It needs the wrap hole; it uses neither `!` nor `if let`.

`a ?? 0` is a diamond: tag test, the payload on one side, the default on the other, both stored
into a `coalesce` slot that the merge block loads:

  $ cat > coal.swift <<'EOF'
  > let a: Int? = 5
  > print(a ?? 0)
  > EOF
  $ ./lab.exe --emit-sil coal.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 5
    %1 = enum #1 (%0) $Int?
    %2 = alloc_stack $Int?  // a
    store %1 to %2
    %4 = load %2 $Int?
    %5 = alloc_stack $Int  // coalesce
    %6 = enum_tag %4
    %7 = integer_literal $Int, 1
    %8 = binop "==" %6, %7 $Bool
    cond_br %8, bb1, bb2
  bb1:
    %9 = enum_payload %4, #0 $Int
    store %9 to %5
    br bb3
  bb2:
    %11 = integer_literal $Int, 0
    store %11 to %5
    br bb3
  bb3:
    %13 = load %5 $Int
    %14 = apply @print(%13)
    return
  }

The right-hand side is evaluated ONLY on the `nil` path — `??` short-circuits, so the `+` below
is generated inside the else block, not before the test:

  $ cat > lazy.swift <<'EOF'
  > let a: Int? = 5
  > let n = 10
  > print(a ?? n + 1)
  > EOF
  $ ./lab.exe --emit-sil lazy.swift | grep -E '^bb|binop|enum_payload|store|load'
  bb0:
    store %1 to %2
    store %4 to %5
    %7 = load %2 $Int?
    %11 = binop "==" %9, %10 $Bool
  bb1:
    %12 = enum_payload %7, #0 $Int
    store %12 to %8
  bb2:
    %14 = load %5 $Int
    %16 = binop "+" %14, %15 $Int
    store %16 to %8
  bb3:
    %18 = load %8 $Int

The result is a plain `Int`, so it composes like one — `(a ?? 0) * 2` multiplies the merged
value:

  $ cat > compose.swift <<'EOF'
  > let a: Int? = nil
  > print((a ?? 3) * 2)
  > EOF
  $ ./lab.exe --emit-sil compose.swift | sed -n '/sil @main/,/^}/p'
  sil @main() -> $() {
  bb0:
    %0 = enum #0 () $Int?
    %1 = alloc_stack $Int?  // a
    store %0 to %1
    %3 = load %1 $Int?
    %4 = alloc_stack $Int  // coalesce
    %5 = enum_tag %3
    %6 = integer_literal $Int, 1
    %7 = binop "==" %5, %6 $Bool
    cond_br %7, bb1, bb2
  bb1:
    %8 = enum_payload %3, #0 $Int
    store %8 to %4
    br bb3
  bb2:
    %10 = integer_literal $Int, 3
    store %10 to %4
    br bb3
  bb3:
    %12 = load %4 $Int
    %13 = integer_literal $Int, 2
    %14 = binop "*" %12, %13 $Int
    %15 = apply @print(%14)
    return
  }

Two `??` in one expression are two diamonds, each with its own slot:

  $ cat > two.swift <<'EOF'
  > let a: Int? = nil
  > let b: Int? = 7
  > print((a ?? 1) + (b ?? 2))
  > EOF
  $ ./lab.exe --emit-sil two.swift | grep -cE 'alloc_stack \$Int  // coalesce'
  2

`??` on a function result works the same way — the subject is any optional expression:

  $ cat > call.swift <<'EOF'
  > func f(_ n: Int) -> Int? {
  >   if n < 0 { return nil }
  >   return n
  > }
  > print(f(-1) ?? -1)
  > EOF
  $ ./lab.exe --emit-sil call.swift | sed -n '/sil @main/,/^}/p'
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 1
    %1 = unop "-" %0 $Int
    %2 = function_ref @f
    %3 = apply %2(%1)
    %4 = alloc_stack $Int  // coalesce
    %5 = enum_tag %3
    %6 = integer_literal $Int, 1
    %7 = binop "==" %5, %6 $Bool
    cond_br %7, bb1, bb2
  bb1:
    %8 = enum_payload %3, #0 $Int
    store %8 to %4
    br bb3
  bb2:
    %10 = integer_literal $Int, 1
    %11 = unop "-" %10 $Int
    store %11 to %4
    br bb3
  bb3:
    %13 = load %4 $Int
    %14 = apply @print(%13)
    return
  }
