# `comparisons/` — swiftml vs. the real swiftc

A suite of **classical, non-trivial programs** compiled by *both* our from-scratch compiler
(`swiftml9`, the full-language LLVM path) and Apple's `swiftc` 6.3.2, asserting **identical stdout
and exit code** at `-Onone` *and* `-O`. This is the behavioral oracle from `CLAUDE.md`, applied to
whole programs rather than single concepts.

## Run it

```sh
cd course
bash comparisons/run.sh          # prints the table
bash comparisons/run.sh --md     # also writes comparisons/RESULTS.md
```

The runner swaps concept-40's `solution/macros.ml` in (the shipped tree is RED-by-design), builds
`swiftml9`, compiles every `programs/*.swift` four ways (swiftml/swiftc × Onone/O), diffs, and
restores the skeleton. Current status: **20/20 MATCH at both `-Onone` and `-O`** (see `RESULTS.md`).

## The programs (`programs/`)

| # | program | exercises |
|---|---------|-----------|
| 01 | insertion_sort | array value-semantics, nested loops, `&&` bounds-guard |
| 02 | quicksort | explicit work-stack, Lomuto partition, in-place swap |
| 03 | mergesort | bottom-up iterative merge, sub-array copy |
| 04 | heapsort | sift-down, build-heap |
| 05 | binary_search | iterative search, returns index |
| 06 | sieve | Eratosthenes, prime counting |
| 07 | nqueens | backtracking recursion, board passed **by value** |
| 08 | hanoi | exponential recursion |
| 09 | ackermann | deep non-primitive recursion |
| 10 | gcd_lcm | Euclid recursion |
| 11 | collatz | longest-chain search |
| 12 | factorize | trial division, **returns `[Int]`** of factors |
| 13 | fib_memo | iterative / recursive / DP-array |
| 14 | rpn | postfix calculator over an `[Int]` value stack |
| 15 | bst | binary search tree as parallel index arrays + iterative in-order |
| 16 | shapes | `protocol` + generic `<T: Shape>` dispatch |
| 17 | bank_errors | `class` reference semantics + `throws`/`do`-`catch` |
| 18 | pipeline | `map`/`filter`/`reduce` + captured variable |
| 19 | matrix | flat-`[Int]` 3×3 multiply |
| 20 | rle | run-length encoding |
| **21** | **sudoku** | backtracking solver over a flat 81-cell board, `&&` guards, deep recursion |
| **22** | **vm** | stack bytecode VM — enum opcodes with payloads decoded + `switch`-dispatched |
| **23** | **dijkstra** | shortest paths on an adjacency matrix, INF sentinel |
| **24** | **bigint_factorial** | arbitrary-precision `50!` via array-of-digits multiply (CoW + grow) |
| **25** | **life** | Conway's Game of Life, a glider over 8 generations |
| **26** | **edit_distance** | Levenshtein DP over a flat `(m+1)×(n+1)` table |
| **27** | **expr_eval** | recursive-descent arithmetic parser (precedence + parens) over a token stream |
| **28** | **kruskal** | minimum spanning tree, union-find, selection-sort on parallel edge arrays |
| **29** | **determinant** | recursive Laplace/cofactor expansion |
| **30** | **shapes_protocols** | protocols + generics + a 3-level class hierarchy + dynamic dispatch together |

## What this suite caught

(See `../PROOFREAD.md` for full detail.)

Whole-program comparison is a much stronger oracle than the per-concept corpora, which use small,
hand-picked inputs. Writing these surfaced **three real compiler bugs** that the concept tests
missed (all now fixed in the live path — see `../PROOFREAD.md`):

1. **`&&`/`||` did not short-circuit** — `while i < n && a[i] < x` evaluated `a[i]` even when
   `i == n`, trapping "Index out of range" where swiftc runs fine. (Broke 01, 04.)
2. **Throwing methods didn't propagate** — `try acct.withdraw(...)` on a `class`/`struct` method
   silently swallowed the thrown error. (Broke 17.)
3. **Functions returning/taking `[Int]` miscompiled** — the signature-resolver didn't understand
   the `[T]` written type, lowering it to `Int`. (Would have broken 12.)

## Subset boundaries the programs respect (v0 limitations, not bugs)

These are documented `swiftml` v0 simplifications; the programs are written to stay inside them.
- `Array` elements are **`Int` only** (no `[String]`, `[[Int]]`, or array-of-enum) — concept 31 v0.
  → `14_rpn` encodes tokens as parallel `[Int]`; `15_bst` uses index arrays, not `class` nodes.
- No `inout`; no optional **class** references (`var next: Node?`) — so linked structures use
  index-into-array representations.
- `else` must sit on the **same line** as the closing `}` (swiftml's parser isn't newline-tolerant
  before `else`, though it is before `catch`) — see `PROOFREAD.md`.
- A collection literal `[ … ]` must be on **one line** — swiftml's lexer treats a newline inside
  `[ ]`/`( )` as a statement separator, where swiftc suppresses it (so `21`/`25`'s boards are
  single-line). Another documented parser divergence.
- No string interpolation (`"\(x)"`), ternary `?:`, or multi-argument `print`.

All three S1 bugs above are now **fixed and backported to the source concepts** (not just the live
binary): `&&`/`||` short-circuit in every `silgen.ml` from concept 08, and throwing methods register
+ error-check from concept 30. The 30-program suite is **30/30 byte-for-byte at `-Onone` and `-O`**.
