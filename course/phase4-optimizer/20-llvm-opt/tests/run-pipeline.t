The whole of Phase 4, end to end. Every program here goes through inline → mem2reg → fold →
simplify → GVN → DCE and then clang, at both levels, and the two levels must agree. These are
the cases that would catch a pass that is subtly wrong in company even though it was right alone.

A `let` inside a hot loop must not grow the stack. This is the alloca-in-loop bug this concept's
benchmark caught: IRGen used to emit the `alloca` in the block where the `alloc_stack` appeared,
so three million iterations allocated three million frames' worth of stack and the program died
around 250k. Every alloca is hoisted to the entry block now, which is what clang does and what
LLVM's own mem2reg requires:

  $ cat > hot.swift <<'PROG'
  > struct P {
  >   var x: Int
  >   var y: Int
  > }
  > var acc = 0
  > for i in 0 ..< 3000000 {
  >   let p = P(x: i % 100, y: i % 37)
  >   acc = acc + p.x + p.y
  > }
  > print(acc)
  > PROG
  $ ./lab.exe --emit-llvm hot.swift | grep -c 'alloca'
  3
  $ ./lab.exe build hot.swift -o hot0 && ./hot0
  202499949
  $ ./lab.exe build hot.swift -O -o hotO && ./hotO
  202499949

Every alloca sits in the entry block, `bb0` — the check is structural, so it holds whatever the
loop body contains:

  $ ./lab.exe --emit-llvm hot.swift | sed -n '/^bb0:/,/^bb[1-9]/p' | grep -c 'alloca'
  3

Inlining, SSA, folding and GVN in one program: a leaf called twice per iteration inside a
condition, with a repeated subexpression in each call:

  $ cat > all.swift <<'PROG'
  > func dot(_ ax: Int, _ ay: Int, _ bx: Int, _ by: Int) -> Int {
  >   return ax * bx + ay * by
  > }
  > var s = 0
  > for i in 1 ..< 1000 {
  >   if dot(i, i, i, i) % 2 == 0 {
  >     s = s + dot(i, 1, 1, i)
  >   }
  > }
  > print(s)
  > PROG
  $ ./lab.exe --sil-opt all.swift | grep -c 'apply %' || true
  0
  $ ./lab.exe build all.swift -o all0 && ./all0
  999000
  $ ./lab.exe build all.swift -O -o allO && ./allO
  999000

Value types, sum types and optionals all survive the full pipeline at both levels — the passes
were written against scalars, and this is where an aggregate that got merged or folded wrongly
shows up as a wrong answer:

  $ cat > mix.swift <<'PROG'
  > struct P {
  >   var x: Int
  >   var y: Int
  > }
  > enum Op {
  >   case add
  >   case mul
  > }
  > func ap(_ o: Op, _ p: P) -> Int {
  >   switch o {
  >   case .add: return p.x + p.y
  >   case .mul: return p.x * p.y
  >   }
  > }
  > func half(_ n: Int) -> Int? {
  >   if n % 2 == 0 { return n / 2 }
  >   return nil
  > }
  > var t = 0
  > for i in 1 ..< 50 {
  >   let p = P(x: i, y: i + 1)
  >   t = t + ap(Op.add, p) + ap(Op.mul, p) + (half(i) ?? 0)
  > }
  > print(t)
  > PROG
  $ ./lab.exe build mix.swift -o mix0 && ./mix0
  44449
  $ ./lab.exe build mix.swift -O -o mixO && ./mixO
  44449

A trap must survive optimization: a force-unwrap of `nil` still aborts with exit 133 at `-O`,
because `Trap` is a terminator and no pass may delete one:

  $ cat > tr.swift <<'PROG'
  > var o: Int? = nil
  > print(o!)
  > PROG
  $ ./lab.exe build tr.swift -O -o trO && sh -c './trO; echo "exit=$?"' 2>/dev/null
  exit=133
