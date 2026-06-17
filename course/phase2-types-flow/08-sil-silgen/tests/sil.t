FileCheck-style checks on `./lab.exe --emit-sil` — the SIL shape (mirrors swiftc -emit-sil).
RED until the SILGen TODO(08) holes are filled.

A function lowers to memory-based SIL: parameters are stored into alloc_stack slots, reads
are loads, and the body ends in a `return`:

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


Control flow becomes a control-flow graph. A `while` produces a header that `cond_br`s to
the body or the exit, and the body branches **back** to the header (the loop's back-edge):

  $ printf 'var n = 0\nwhile n < 3 {\n  n = n + 1\n}\n' > w.swift
  $ ./lab.exe --emit-sil w.swift | grep -oE "cond_br %[0-9]+, bb[0-9]+, bb[0-9]+" | head -1
  cond_br %5, bb2, bb3
  $ ./lab.exe --emit-sil w.swift | grep -c "br bb1"
  2

An `if`/`else` builds a diamond — a `cond_br` to two blocks that both branch to a merge:

  $ printf 'let x = 1\nif x < 0 {\n  print(x)\n} else {\n  print(0)\n}\n' > i.swift
  $ ./lab.exe --emit-sil i.swift | grep -c "cond_br"
  1
