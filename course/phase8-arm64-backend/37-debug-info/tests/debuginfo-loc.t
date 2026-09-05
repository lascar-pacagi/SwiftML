TODO(37) — the `.loc` stream. Every SIL value carries the source line of the statement it came
from (SILGen stamps it; that part is given). Your job is to turn that per-value line into a
directive stream: a `.loc` whenever the line CHANGES, and none when it doesn't.

The asm names its source file once with `.file`, then marks each statement's line. Lines 1 and 4
carry no code of their own — the `func` header and the closing brace — so no `.loc` names them.

  $ cat > x.swift <<'SWIFT'
  > func square(_ n: Int) -> Int {
  >   let r = n * n
  >   return r
  > }
  > let a = 6
  > let b = square(a)
  > print(b)
  > print(a + b)
  > SWIFT
  $ ./lab.exe --emit-asm x.swift | grep -E '^	\.file'
  	.file	1 "x.swift"
  $ ./lab.exe --emit-asm x.swift | grep -E '^	\.loc'
  	.loc	1 2 0
  	.loc	1 3 0
  	.loc	1 5 0
  	.loc	1 6 0
  	.loc	1 7 0
  	.loc	1 8 0

One directive per statement, not per instruction: a statement that lowers to a dozen
instructions still gets a single `.loc`, because the line has not changed between them.

  $ printf 'let a = 1 + 2 * 3 - 4 / 2 + 5 * 6 - 7\nprint(a)\n' > wide.swift
  $ ./lab.exe --emit-asm wide.swift | grep -c -E '^	\.loc' || true
  2

The stream follows the CODE, not the source. A `while` marks its condition line once, at the
header block; the back-edge jumps to that same address, and there is only one address to map. So
a loop contributes one directive per line of it, not one per iteration.

  $ printf 'var t = 0\nvar i = 0\nwhile i < 3 {\n  t = t + i\n  i = i + 1\n}\nprint(t)\n' > loop.swift
  $ ./lab.exe --emit-asm loop.swift | grep -E '^	\.loc'
  	.loc	1 1 0
  	.loc	1 2 0
  	.loc	1 3 0
  	.loc	1 4 0
  	.loc	1 5 0
  	.loc	1 7 0

The directives are inert: the program runs and matches swiftc, exactly as it did in concept 36.

  $ ./lab.exe build x.swift --native -o x && ./x
  36
  42
  $ swiftc -Onone x.swift -o x_sw && ./x_sw
  36
  42
