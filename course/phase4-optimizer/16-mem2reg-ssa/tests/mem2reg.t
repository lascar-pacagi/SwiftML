mem2reg promotes alloc_stack/load/store to SSA values threaded through basic-block arguments,
and `-O` must still match `swiftc`. RED until the TODO(16) renaming hole is filled.

Raw SIL for a loop is memory-heavy (the accumulator and induction var live in slots):

  $ cat > l.swift <<'EOF'
  > var s = 0
  > for i in 0 ..< 3 { s = s + i }
  > print(s)
  > EOF
  $ ./lab.exe --emit-sil l.swift | grep -cE 'alloc_stack|load|store'
  11

After mem2reg the slots are gone — the loop carries its values as block arguments (the SSA "phi"):

  $ ./lab.exe --sil-opt l.swift | grep -cE 'alloc_stack| load | store ' || true
  0
  $ ./lab.exe --sil-opt l.swift | grep -oE 'bb[0-9]+\(' | head -1
  bb1(

`-O` preserves behavior across loops, recursion, and structs:

  $ ./lab.exe build l.swift -O -o l && ./l
  3

  $ cat > fib.swift <<'EOF'
  > func fib(_ n: Int) -> Int {
  >   if n < 2 { return n }
  >   return fib(n - 1) + fib(n - 2)
  > }
  > print(fib(20))
  > EOF
  $ ./lab.exe build fib.swift -O -o fib && ./fib
  6765

  $ cat > sp.swift <<'EOF'
  > struct P { var x: Int; var y: Int }
  > var s = 0
  > for i in 0 ..< 4 { let p = P(x: i, y: i * i); s = s + p.x + p.y }
  > print(s)
  > EOF
  $ ./lab.exe build sp.swift -O -o sp && ./sp
  20
