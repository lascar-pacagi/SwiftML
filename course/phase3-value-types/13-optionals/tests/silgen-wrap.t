The first silgen hole, TODO(13) in `gen_expr_as`: the IMPLICIT WRAP. Wherever a `T?` is
expected, `nil` becomes `.none` (tag 0), a bare `T` is wrapped as `.some` (tag 1, one payload),
and a value that is ALREADY a `T?` passes through untouched. `--emit-sil` stops after SILGen, so
this file needs no IRGen, and it uses none of `!`, `??` or `if let` — the other three holes.

`let a: Int? = 5` stores `.some(5)` — the annotation is what makes the wrap happen, and the
slot's type is `$Int?`:

  $ cat > some.swift <<'EOF'
  > let a: Int? = 5
  > EOF
  $ ./lab.exe --emit-sil some.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 5
    %1 = enum #1 (%0) $Int?
    %2 = alloc_stack $Int?  // a
    store %1 to %2
    return
  }

`let b: Int? = nil` stores `.none`: tag 0, no payload — `nil` is not a pointer, it is a case:

  $ cat > none.swift <<'EOF'
  > let b: Int? = nil
  > EOF
  $ ./lab.exe --emit-sil none.swift | grep -E 'enum|alloc_stack'
    %0 = enum #0 () $Int?
    %1 = alloc_stack $Int?  // b

Assigning to an optional `var` wraps too. This is the once-shipped miscompile: without the wrap
the raw `7` went into a `{tag, payload}` slot, so the tag read back as 7 and the value as junk:

  $ cat > assign.swift <<'EOF'
  > var x: Int? = 5
  > x = 7
  > x = nil
  > EOF
  $ ./lab.exe --emit-sil assign.swift | grep -E 'enum|store'
    %1 = enum #1 (%0) $Int?
    store %1 to %2
    %5 = enum #1 (%4) $Int?
    store %5 to %2
    %7 = enum #0 () $Int?
    store %7 to %2

A `-> Int?` function wraps at every `return`, the bare value and the `nil` alike:

  $ cat > ret.swift <<'EOF'
  > func f(_ n: Int) -> Int? {
  >   if n < 0 { return nil }
  >   return n * 2
  > }
  > EOF
  $ ./lab.exe --emit-sil ret.swift | sed -n '/sil @f/,/^}/p'
  sil @f(%0 : $Int) -> $Int? {
  bb0:
    %1 = alloc_stack $Int  // n
    store %0 to %1
    %3 = load %1 $Int
    %4 = integer_literal $Int, 0
    %5 = binop "<" %3, %4 $Bool
    cond_br %5, bb1, bb2
  bb1:
    %6 = enum #0 () $Int?
    return %6
  bb2:
    %7 = load %1 $Int
    %8 = integer_literal $Int, 2
    %9 = binop "*" %7, %8 $Int
    %10 = enum #1 (%9) $Int?
    return %10
  }

An argument is wrapped at the CALL, against the parameter's type:

  $ cat > arg.swift <<'EOF'
  > func g(_ o: Int?) -> Int { return 0 }
  > let n = g(4)
  > EOF
  $ ./lab.exe --emit-sil arg.swift | sed -n '/sil @main/,/^}/p'
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 4
    %1 = enum #1 (%0) $Int?
    %2 = function_ref @g
    %3 = apply %2(%1)
    %4 = alloc_stack $Int  // n
    store %3 to %4
    return
  }

A value that is ALREADY optional is not wrapped twice — passing `a` on gives one `enum`, the
one that built it:

  $ cat > passthru.swift <<'EOF'
  > func g(_ o: Int?) -> Int { return 0 }
  > let a: Int? = 5
  > let n = g(a)
  > EOF
  $ ./lab.exe --emit-sil passthru.swift | grep -cE '= enum '
  1

A struct field declared `Int?` is wrapped by the memberwise initializer, per field:

  $ cat > field.swift <<'EOF'
  > struct Box {
  >   var v: Int?
  >   var n: Int
  > }
  > let b = Box(v: 3, n: 1)
  > let e = Box(v: nil, n: 2)
  > EOF
  $ ./lab.exe --emit-sil field.swift | grep -E 'enum|struct '
  struct Box { v: Int?; n: Int }
    %1 = enum #1 (%0) $Int?
    %3 = struct (%1, %2) $Box
    %6 = enum #0 () $Int?
    %8 = struct (%6, %7) $Box

A write to an optional FIELD wraps against the field's type — `b.v = nil` stores `.none` into
the field's address, and `b.v = 9` stores `.some(9)` (writing the raw value there would corrupt
the tag exactly as the `var` case above did):

  $ cat > setfield.swift <<'EOF'
  > struct Box {
  >   var v: Int?
  >   var n: Int
  > }
  > var b = Box(v: 3, n: 1)
  > b.v = nil
  > b.v = 9
  > EOF
  $ ./lab.exe --emit-sil setfield.swift | grep -E 'enum|struct_element_addr|store'
    %1 = enum #1 (%0) $Int?
    store %3 to %4
    %6 = enum #0 () $Int?
    %7 = struct_element_addr %4, #0
    store %6 to %7
    %10 = enum #1 (%9) $Int?
    %11 = struct_element_addr %4, #0
    store %10 to %11

`a == nil` is GIVEN and needs no wrap: it reads the tag and compares it with 0:

  $ cat > isnil.swift <<'EOF'
  > let a: Int? = 5
  > print(a == nil)
  > print(a != nil)
  > EOF
  $ ./lab.exe --emit-sil isnil.swift | grep -E 'enum_tag|binop'
    %5 = enum_tag %4
    %7 = binop "==" %5, %6 $Bool
    %10 = enum_tag %9
    %12 = binop "!=" %10, %11 $Bool
