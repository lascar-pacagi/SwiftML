The pass manager, through `--sil-opt`. Needs the `TODO(15)` hole in `run_pipeline`: every pass
over every function, in order. The only pass it needs here is the GIVEN `dead_instr_elim`, so
this file goes green before `constant_fold` exists — `a + 1` below reads `a` from a slot, which
folding cannot see through anyway. Each case prints a raw count, then the optimized one.

`a + 1` as a statement is a binop nobody uses: raw SIL has 1, `--sil-opt` has 0:

  $ printf 'let a = 1\na + 1\nprint(a)\n' > dead.swift
  $ ./lab.exe --emit-sil dead.swift | grep -c 'binop'; ./lab.exe --sil-opt dead.swift | grep -c 'binop' || true
  1
  0

The `store` and the `print` are side effects: only the binop goes, those two stay:

  $ ./lab.exe --sil-opt dead.swift | grep -o 'store\|apply @print\|binop'
  store
  apply @print

The manager visits every function, not just `main`: a dead `x + 1` inside `f` goes too:

  $ printf 'func f(_ x: Int) -> Int {\n  x + 1\n  return x\n}\nprint(f(1))\n' > fn.swift
  $ ./lab.exe --emit-sil fn.swift | grep -c 'binop'; ./lab.exe --sil-opt fn.swift | grep -c 'binop' || true
  1
  0

Both functions are still there afterwards — the manager rebuilds the module, it drops nothing:

  $ ./lab.exe --sil-opt fn.swift | grep '^sil @\|binop'
  sil @f(%0 : $Int) -> $Int {
  sil @main() -> $() {

`-O` builds a binary that behaves like the unoptimized one: with the binop gone it prints 1:

  $ ./lab.exe --sil-opt dead.swift | grep -c 'binop' || true; ./lab.exe build dead.swift -O -o deadO && ./deadO
  0
  1
