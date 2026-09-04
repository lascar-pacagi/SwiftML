TODO(08) — the `while` LOOP. The shape a tree cannot hold: a header block that re-tests the
condition, a body that branches BACK to it, and an exit block. The back-edge is the whole
point of moving from the AST to a CFG.

A counted `while` puts the test in its own header block: the entry `br`s into it, the header
`cond_br`s to the body or the exit, and the body ends in the back-edge `br` to the header.

  $ printf 'var n = 0\nwhile n < 3 {\n  n = n + 1\n}\nprint(n)\n' > w.swift
  $ ./lab.exe --emit-sil w.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 0
    %1 = alloc_stack $Int  // n
    store %0 to %1
    br bb1
  bb1:
    %3 = load %1 $Int
    %4 = integer_literal $Int, 3
    %5 = binop "<" %3, %4 $Bool
    cond_br %5, bb2, bb3
  bb2:
    %6 = load %1 $Int
    %7 = integer_literal $Int, 1
    %8 = binop "+" %6, %7 $Int
    store %8 to %1
    br bb1
  bb3:
    %10 = load %1 $Int
    %11 = apply @print(%10)
    return
  }

Two blocks branch to the header — the entry on the way in, the body on the way round.

  $ ./lab.exe --emit-sil w.swift | grep -c "br bb1" || true
  2

`while false { }` still builds all three blocks: SILGen does not know the condition is a
constant, and folding it away is Phase 4's job (concept 17).

  $ printf 'while false {\n  print(1)\n}\nprint(0)\n' > wf.swift
  $ ./lab.exe --emit-sil wf.swift
  sil @main() -> $() {
  bb0:
    br bb1
  bb1:
    %0 = integer_literal $Bool, false
    cond_br %0, bb2, bb3
  bb2:
    %1 = integer_literal $Int, 1
    %2 = apply @print(%1)
    br bb1
  bb3:
    %3 = integer_literal $Int, 0
    %4 = apply @print(%3)
    return
  }

Nested `while`s give two headers, each reached twice — once on the way in, once round its
own back-edge.

  $ printf 'var i = 0\nwhile i < 2 {\n  var j = 0\n  while j < 2 {\n    j = j + 1\n  }\n  i = i + 1\n}\nprint(i)\n' > wn.swift
  $ ./lab.exe --emit-sil wn.swift | grep -oE "br bb[0-9]+" | sort | uniq -c
     2 br bb1
     2 br bb4

The verifier accepts the loop: every branch target exists, so `--emit-sil` exits 0.

  $ ./lab.exe --emit-sil wn.swift > /dev/null 2> verr.txt; echo "exit=$?"
  exit=0
  $ cat verr.txt
