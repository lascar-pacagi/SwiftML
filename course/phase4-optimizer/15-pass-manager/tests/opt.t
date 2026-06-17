The optimizer: `--emit-sil` is raw SIL, `--sil-opt` runs the `-O` pipeline, and `-O` must not
change behavior. RED until the `run_pipeline` + `constant_fold` TODO(15) holes are filled.

Raw SIL has the arithmetic spelled out as instructions:

  $ printf 'print(1 + 2 * 3)\n' > c.swift
  $ ./lab.exe --emit-sil c.swift | grep -c 'binop'
  2

Optimized SIL has folded it to a single literal — and dead-code elimination removed the leftovers:

  $ ./lab.exe --sil-opt c.swift | grep -c 'binop' || true
  0
  $ ./lab.exe --sil-opt c.swift | grep -o 'integer_literal $Int, 7'
  integer_literal $Int, 7

`-O` preserves behavior — an optimized program prints the same thing:

  $ ./lab.exe build c.swift -O -o cO && ./cO
  7

A program with a loop, optimized, still runs correctly:

  $ cat > s.swift <<'EOF'
  > var s = 0
  > for i in 0 ..< 5 { s = s + i * 2 }
  > print(s)
  > EOF
  $ ./lab.exe build s.swift -O -o sO && ./sO
  20
