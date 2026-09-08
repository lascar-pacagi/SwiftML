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

`hi` is evaluated ONCE, before the loop. The bound here is `k * 2`, and nothing else in the
program multiplies, so every `binop "*"` in the output IS the bound — there must be exactly one:

  $ printf 'var t = 0\nlet k = 2\nfor i in 0 ..< k * 2 {\n  t = t + i\n}\nprint(t)\n' > fh.swift
  $ ./lab.exe --emit-sil-canon fh.swift | grep -c 'binop "\*"'
  1

And it is not in the loop. `bb1` is the header — the block the back edge returns to — and all it
does is re-read `i` and compare it against the bound computed before the loop began. The value
numbers are blanked, because which `%n` the bound landed on depends on the order you emitted the
entry block in, and that is not what this case is about:

  $ ./lab.exe --emit-sil-canon fh.swift | sed -n '/^bb1:/,/cond_br/p' | sed 's/%[0-9][0-9]*/%_/g'
  bb1:
    %_ = load %_ $Int
    %_ = binop "<" %_, %_ $Bool
    cond_br %_, bb2, bb3

The latch is a separate block, so the body's fall-through and the increment are not the same
block: the body ends in a `br` to the latch, and the latch carries the back-edge.

  $ ./lab.exe --emit-sil-canon fh.swift | grep -oE "br bb[0-9]+" | sort | uniq -c
     2 br bb1

The verifier accepts the desugaring: `--emit-sil` exits 0 and says nothing on stderr.

  $ ./lab.exe --emit-sil-canon fh.swift > /dev/null 2> verr.txt; echo "exit=$?"
  exit=0
  $ cat verr.txt
