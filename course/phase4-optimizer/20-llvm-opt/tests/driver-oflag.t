The `TODO(20)` hole is one line in `driver.ml` — the `-O2` that `run_clang` hands to clang when
`-O` is on — and this file is the whole of what that line changes. `-Onone` never touches it, so
those cases are green on the untouched skeleton; every `-O` case raises until it is filled.

`-Onone` compiles and runs on the skeleton, because its flag is already `-O0`:

  $ cat > q.swift <<'PROG'
  > func sq(_ x: Int) -> Int {
  >   return x * x
  > }
  > print(sq(5) + sq(6))
  > PROG
  $ ./lab.exe build q.swift -o q0 && ./q0
  61

`-O` must produce a binary that prints exactly the same thing. LLVM's optimizer is not allowed to
change an answer any more than ours is:

  $ ./lab.exe build q.swift -O -o qO && ./qO
  61

The two levels are visible in the LLVM IR that goes IN: `-O` runs our SIL pipeline first, so the
module clang receives has already lost the call and the arithmetic, while `-Onone` hands over the
whole thing. (What clang then does to it is not in the IR we print — that is the point of §5.)

  $ ./lab.exe --emit-llvm q.swift | grep -c 'define i64 @sq'
  1
  $ ./lab.exe --emit-llvm q.swift -O | grep -c 'define i64 @sq' || true
  0
  $ ./lab.exe --emit-llvm q.swift -O | grep -oE '61'
  61

THE OBSERVABLE DIFFERENCE, and the reason a stubbed `-O0` here would not pass: LLVM at `-O2` does
TAIL-CALL ELIMINATION, which we do not. Sixty million frames of self-recursion would need
gigabytes of stack, so at `-O0` the program dies — the shell reports the segfault as exit 139 —
while at `-O2` the recursion is a loop and it answers immediately:

  $ cat > tc.swift <<'PROG'
  > func count(_ n: Int, _ acc: Int) -> Int {
  >   if n == 0 { return acc }
  >   return count(n - 1, acc + 1)
  > }
  > print(count(60000000, 0))
  > PROG
  $ ./lab.exe build tc.swift -o tc0 && sh -c './tc0; echo "exit=$?"' 2>/dev/null
  exit=139
  $ ./lab.exe build tc.swift -O -o tcO && sh -c './tcO; echo "exit=$?"' 2>/dev/null
  60000000
  exit=0

That is the honest shape of this concept: the flag is trivial, what it buys is not, and the only
way to see the rest of it is to measure — `make bench C=phase4-optimizer/20-llvm-opt`, §5.
