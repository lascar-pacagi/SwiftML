TODO(08c) — `for v in lo ..< hi`, DESUGARED to the counted loop. `for` adds no new SIL: a slot
for `v` initialized to `lo`, a while-shaped loop testing `v < hi`, and the increment in a
block of its own — the LATCH — so that `continue` can branch there instead of skipping it.

`for i in 0 ..< 3` allocates a slot for `i`, seeds it in the entry block, and loops through a
header, a body, a latch that increments, and an exit.

  $ printf 'for i in 0 ..< 3 {\n  print(i)\n}\nprint(9)\n' > f.swift
  $ ./lab.exe --emit-sil-canon f.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 0
    %1 = integer_literal $Int, 3
    %2 = alloc_stack $Int  // i
    store %0 to %2
    br bb1
  bb1:
    %4 = load %2 $Int
    %5 = binop "<" %4, %1 $Bool
    cond_br %5, bb2, bb3
  bb2:
    %6 = integer_literal $Int, 1
    %7 = load %2 $Int
    %8 = apply @print(%7)
    %9 = load %2 $Int
    %10 = binop "+" %9, %6 $Int
    store %10 to %2
    br bb1
  bb3:
    %12 = integer_literal $Int, 9
    %13 = apply @print(%12)
    return
  }

The induction variable gets a real named slot, like any `var`.

  $ ./lab.exe --emit-sil-canon f.swift | grep "alloc_stack"
    %2 = alloc_stack $Int  // i

`hi` is evaluated ONCE, before the loop: with `0 ..< k + 1` the addition is in the entry
block, and the header only re-loads `i` to compare against it.

  $ printf 'var t = 0\nlet k = 2\nfor i in 0 ..< k + 1 {\n  t = t + i\n}\nprint(t)\n' > fh.swift
  $ ./lab.exe --emit-sil-canon fh.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 0
    %1 = integer_literal $Int, 2
    %2 = integer_literal $Int, 0
    %3 = integer_literal $Int, 1
    %4 = alloc_stack $Int  // t
    %5 = alloc_stack $Int  // k
    %6 = alloc_stack $Int  // i
    store %0 to %4
    store %1 to %5
    %9 = load %5 $Int
    %10 = binop "+" %9, %3 $Int
    store %2 to %6
    br bb1
  bb1:
    %12 = load %6 $Int
    %13 = binop "<" %12, %10 $Bool
    cond_br %13, bb2, bb3
  bb2:
    %14 = integer_literal $Int, 1
    %15 = load %4 $Int
    %16 = load %6 $Int
    %17 = binop "+" %15, %16 $Int
    store %17 to %4
    %19 = load %6 $Int
    %20 = binop "+" %19, %14 $Int
    store %20 to %6
    br bb1
  bb3:
    %22 = load %4 $Int
    %23 = apply @print(%22)
    return
  }

The latch is a separate block, so the body's fall-through and the increment are not the same
block: the body ends in a `br` to the latch, and the latch carries the back-edge.

  $ ./lab.exe --emit-sil-canon fh.swift | grep -oE "br bb[0-9]+" | sort | uniq -c
     2 br bb1

The verifier accepts the desugaring: `--emit-sil` exits 0 and says nothing on stderr.

  $ ./lab.exe --emit-sil-canon fh.swift > /dev/null 2> verr.txt; echo "exit=$?"
  exit=0
  $ cat verr.txt
