TODO(08a) — the MEMORY MODEL, and the SIL vocabulary every control-flow hole has to fit into.
Raw SIL keeps each variable in an `alloc_stack` slot and touches it only through `load` and
`store`; there is no SSA here, and Phase-4's mem2reg is the pass that later takes it away.
Nothing in this file branches, so it reports on TODO(08a) alone — it can go green while every
TODO(08c) in `gen_stmt` still raises.

`let x = 1` becomes an alloc_stack slot, a store, and a load at the use.

  $ printf 'let x = 1\nprint(x)\n' > let.swift
  $ ./lab.exe --emit-sil let.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 1
    %1 = alloc_stack $Int  // x
    store %0 to %1
    %3 = load %1 $Int
    %4 = apply @print(%3)
    return
  }

A parameter is a SIL value stored straight into a slot of its own.

  $ printf 'func id(_ x: Int) -> Int {\n  return x\n}\n' > id.swift
  $ ./lab.exe --emit-sil id.swift
  sil @id(%0 : $Int) -> $Int {
  bb0:
    %1 = alloc_stack $Int  // x
    store %0 to %1
    %3 = load %1 $Int
    return %3
  }
  
  sil @main() -> $() {
  bb0:
    return
  }

Reassignment stores over the same slot instead of allocating a second one.

  $ printf 'var n = 1\nn = n + 1\nprint(n)\n' > var.swift
  $ ./lab.exe --emit-sil var.swift | grep -c "alloc_stack" || true
  1
  $ ./lab.exe --emit-sil var.swift | grep -c "store" || true
  2

A call lowers to a `function_ref` and an `apply`, and binding its result goes through a slot
like any other value; `print` is the one builtin.

  $ printf 'func two() -> Int {\n  return 2\n}\nlet t = two()\nprint(t)\n' > call.swift
  $ ./lab.exe --emit-sil call.swift | grep "function_ref\|apply\|alloc_stack"
    %0 = function_ref @two
    %1 = apply %0()
    %2 = alloc_stack $Int  // t
    %5 = apply @print(%4)

`&&` already short-circuits: the given gen_expr builds the same diamond you are about to
build for `if`, merging the two answers through a slot.

  $ printf 'let n = 3\nlet b = n > 1 && n < 5\nprint(b)\n' > and.swift
  $ ./lab.exe --emit-sil and.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 3
    %1 = alloc_stack $Int  // n
    store %0 to %1
    %3 = load %1 $Int
    %4 = integer_literal $Int, 1
    %5 = binop ">" %3, %4 $Bool
    %6 = alloc_stack $Bool  // $and
    store %5 to %6
    cond_br %5, bb1, bb2
  bb1:
    %8 = load %1 $Int
    %9 = integer_literal $Int, 5
    %10 = binop "<" %8, %9 $Bool
    store %10 to %6
    br bb2
  bb2:
    %12 = load %6 $Bool
    %13 = alloc_stack $Bool  // b
    store %12 to %13
    %15 = load %13 $Bool
    %16 = apply @print(%15)
    return
  }
