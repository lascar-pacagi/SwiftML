The whole section at once, on `tests/programs/controlflow.swift` — functions, recursion, mutual
recursion, if/else-if, while, for, break, continue, nested loops, short-circuit, an early
`return`, Double. Every earlier file checks one shape in isolation; this one is here to catch the
lowering that gets each shape right and still falls apart when they are combined.

It deliberately does NOT compare the SIL. A sixty-block dump tells you that something moved, not
what, and two correct lowerings differ in it anyway. What it compares are facts that hold for any
correct lowering of this program, each on its own line, so a failure is one number.

The strongest one first: the verifier walks every block and every branch target, so if any block
lost its terminator or names a block that does not exist, this is where it shows.

  $ P=../../../tests/programs/controlflow.swift
  $ ./lab.exe --emit-sil $P > sil.txt 2> err.txt; echo "exit=$?"
  exit=0
  $ wc -c < err.txt | tr -d ' '
  0

One SIL function per `func`, plus `@main` for the top level — nine. A missing one means a
declaration was not lowered at all:

  $ grep -c '^sil @' sil.txt
  9

Every decision in the program emits exactly one `cond_br`: the `if`s, the loop headers, and each
`&&` / `||`, which are branches too. This count does not depend on how you lay the blocks out, so
it is a real check on the lowering rather than on your block numbering. One short of it usually
means a short-circuit operator was lowered as arithmetic:

  $ grep -c 'cond_br' sil.txt
  23

Two blocks are genuinely unreachable, and both are merges after an `if` whose arms all return —
`maxOf` and `sign`. More than two means a block was left dangling, which is what an orphaned latch
looks like from here:

  $ grep -c 'unreachable' sil.txt
  2
