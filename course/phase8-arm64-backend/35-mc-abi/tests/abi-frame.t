This file is GREEN before you start: it covers the frame machinery this concept gives you, and
fixes the boundary your two holes have to respect. Read it first.

A function of eight arguments or fewer is untouched: no store into the outgoing area beyond the
one `print` makes for its own variadic argument.

  $ cat > small.swift <<'SWIFT'
  > func f(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ g: Int, _ h: Int, _ i: Int) -> Int {
  >   return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * g + 7 * h + 8 * i
  > }
  > print(f(1, 2, 3, 4, 5, 6, 7, 8))
  > SWIFT
  $ ./lab.exe --emit-asm small.swift | grep -E -c '	str	x[0-9]+, \[sp, #8\]' || true
  0
  $ ./lab.exe build small.swift --native -o small && ./small
  204

The prologue is large-frame-safe: the frame record goes down first and is stored at offset 0, so
`stp`/`ldp` stay inside their 7-bit scaled immediate however big the frame is, and a locals area
past `sub`'s 12-bit immediate is carved in steps. A 200-variable `main` is both.

  $ i=0; sum=""; : > many.swift
  > while [ $i -lt 200 ]; do echo "let z$i = $i" >> many.swift; sum="$sum+z$i"; i=$((i+1)); done
  > echo "print(0$sum)" >> many.swift
  $ ./lab.exe --emit-asm many.swift | grep -E '	(stp|ldp)	' | grep -E -c -v '#0\]' || true
  0
  $ ./lab.exe build many.swift --native -o many && ./many
  19900
  $ swiftc -Onone many.swift -o many_sw && ./many_sw
  19900
