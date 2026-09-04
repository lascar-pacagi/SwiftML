TODO(08) — the `if` DIAMOND. `--emit-sil` stops right after SILGen and the verifier, so what
these cases read is exactly the graph you built: a `cond_br` out of the current block, one
block per branch, and a merge block that execution continues from.

`if c { A } else { B }` splits into then, merge and else blocks, both branches ending `br` to
the merge, and the statement after the `if` lands in the merge.

  $ printf 'let x = 1\nif x < 0 {\n  print(x)\n} else {\n  print(0)\n}\nprint(9)\n' > ifelse.swift
  $ ./lab.exe --emit-sil ifelse.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 1
    %1 = alloc_stack $Int  // x
    store %0 to %1
    %3 = load %1 $Int
    %4 = integer_literal $Int, 0
    %5 = binop "<" %3, %4 $Bool
    cond_br %5, bb1, bb3
  bb1:
    %6 = load %1 $Int
    %7 = apply @print(%6)
    br bb2
  bb2:
    %10 = integer_literal $Int, 9
    %11 = apply @print(%10)
    return
  bb3:
    %8 = integer_literal $Int, 0
    %9 = apply @print(%8)
    br bb2
  }

Without an `else` there is no third block: the false edge of the `cond_br` is the merge.

  $ printf 'let x = 1\nif x > 0 {\n  print(x)\n}\nprint(9)\n' > ifonly.swift
  $ ./lab.exe --emit-sil ifonly.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 1
    %1 = alloc_stack $Int  // x
    store %0 to %1
    %3 = load %1 $Int
    %4 = integer_literal $Int, 0
    %5 = binop ">" %3, %4 $Bool
    cond_br %5, bb1, bb2
  bb1:
    %6 = load %1 $Int
    %7 = apply @print(%6)
    br bb2
  bb2:
    %8 = integer_literal $Int, 9
    %9 = apply @print(%8)
    return
  }

When both branches `return`, the merge block is genuinely unreachable and keeps the
`unreachable` terminator — a valid terminator, not an unfilled one.

  $ printf 'func pick(_ c: Bool) -> Int {\n  if c {\n    return 1\n  } else {\n    return 2\n  }\n}\nprint(pick(true))\n' > pick.swift
  $ ./lab.exe --emit-sil pick.swift
  sil @pick(%0 : $Bool) -> $Int {
  bb0:
    %1 = alloc_stack $Bool  // c
    store %0 to %1
    %3 = load %1 $Bool
    cond_br %3, bb1, bb3
  bb1:
    %4 = integer_literal $Int, 1
    return %4
  bb2:
    unreachable
  bb3:
    %5 = integer_literal $Int, 2
    return %5
  }
  
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Bool, true
    %1 = function_ref @pick
    %2 = apply %1(%0)
    %3 = apply @print(%2)
    return
  }

An `else if` chain is an `if` nested in an else block, so it emits a second `cond_br`.

  $ printf 'let n = 2\nif n == 1 {\n  print(1)\n} else if n == 2 {\n  print(2)\n} else {\n  print(0)\n}\n' > chain.swift
  $ ./lab.exe --emit-sil chain.swift | grep -c "cond_br" || true
  2

The SIL verifier runs on every `--emit-sil`, so a branch to a block you never created would
fail here rather than in concept 09; a clean lowering exits 0 and prints nothing to stderr.

  $ ./lab.exe --emit-sil chain.swift > /dev/null 2> verr.txt; echo "exit=$?"
  exit=0
  $ cat verr.txt
