TODO(36) — the invalidation rules, which are the whole game. Forwarding is only sound while the
bookkeeping is true, so the interesting cases are the ones where the pass must NOT rewrite.

Anything that writes a register forgets what that register held. Here `x19` is overwritten
between the store and the reload, so the reload has to stay a load — turning it into `mov x20,
x19` would read the new value.

  $ cat > c.swift <<'SWIFT'
  > var x = 1
  > var y = 2
  > x = x + y
  > y = x + y
  > x = y * 2
  > print(x)
  > print(y)
  > SWIFT
  $ ./lab.exe build c.swift --native -o c && ./c
  10
  5
  $ ./lab.exe build c.swift --native --no-peephole -o c0 && ./c0
  10
  5
  $ swiftc -Onone c.swift -o c_sw && ./c_sw
  10
  5

A call clobbers broadly, so the table is dropped at a `bl`. A program that reads a variable,
calls a function, and reads the same variable again must reload it afterwards.

  $ cat > k.swift <<'SWIFT'
  > func twice(_ n: Int) -> Int { return n + n }
  > let v = 21
  > let a = twice(v)
  > let b = twice(v)
  > print(a + b + v)
  > SWIFT
  $ ./lab.exe build k.swift --native -o k && ./k
  105
  $ ./lab.exe build k.swift --native --no-peephole -o k0 && ./k0
  105
  $ swiftc -Onone k.swift -o k_sw && ./k_sw
  105

The table never crosses a block boundary: a value stored before a branch cannot be assumed to be
in a register at the label, because control can arrive there from somewhere else. A loop is the
test — the header is reached from two directions.

  $ cat > l.swift <<'SWIFT'
  > var t = 0
  > var i = 0
  > while i < 6 {
  >   t = t + i * i
  >   i = i + 1
  > }
  > print(t)
  > print(i)
  > SWIFT
  $ ./lab.exe build l.swift --native -o l && ./l
  55
  6
  $ ./lab.exe build l.swift --native --no-peephole -o l0 && ./l0
  55
  6
  $ swiftc -Onone l.swift -o l_sw && ./l_sw
  55
  6

Being local is a limit, not just a safety rule. The pass trims the two loads it can see inside
the loop body, but the reloads that OPEN each iteration survive: `t` and `i` live in memory, the
header is reached from two edges, and forwarding across those edges is exactly what the table's
per-block reset forbids. Removing that redundancy needs mem2reg — concept 34's exercise — not
a bigger peephole.

  $ ./lab.exe --emit-asm --no-peephole l.swift | grep -c '	ldr	' || true
  11
  $ ./lab.exe --emit-asm l.swift | grep -c '	ldr	' || true
  9
