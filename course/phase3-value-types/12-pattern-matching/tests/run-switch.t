The programs of concept 12, BUILT and RUN. It needs the silgen hole — the sema hole only adds a
rejection, so this file goes green as soon as the dispatch chain is lowered. These are the
behaviours the concept claims; `oracle.t` checks the same kind of program against swiftc.

`switch` finally takes an enum APART: the areas of a rect, a circle and a payload-free case:

  $ cat > area.swift <<'EOF'
  > enum Shape {
  >   case circle(Int)
  >   case rect(Int, Int)
  >   case dot
  > }
  > func area(_ s: Shape) -> Int {
  >   switch s {
  >   case .circle(let r): return r * r
  >   case .rect(let w, let h): return w * h
  >   case .dot: return 0
  >   }
  > }
  > print(area(Shape.rect(3, 4)))
  > print(area(Shape.circle(5)))
  > print(area(Shape.dot))
  > EOF
  $ ./lab.exe build area.swift -o area && ./area
  12
  25
  0

An ADT plus a switch is an interpreter — Milestone M3 in miniature:

  $ cat > eval.swift <<'EOF'
  > enum Op {
  >   case lit(Int)
  >   case add(Int, Int)
  >   case mul(Int, Int)
  > }
  > func eval(_ o: Op) -> Int {
  >   switch o {
  >   case .lit(let n): return n
  >   case .add(let a, let b): return a + b
  >   case .mul(let a, let b): return a * b
  >   }
  > }
  > print(eval(Op.lit(9)))
  > print(eval(Op.add(3, 4)))
  > print(eval(Op.mul(6, 7)))
  > EOF
  $ ./lab.exe build eval.swift -o eval && ./eval
  9
  7
  42

A switch used as a STATEMENT assigns instead of returning, and control joins after it:

  $ cat > stmt.swift <<'EOF'
  > enum Light { case red, amber, green }
  > func wait(_ l: Light) -> Int {
  >   var s = 0
  >   switch l {
  >   case .red: s = 30
  >   case .amber: s = 5
  >   case .green: s = 0
  >   }
  >   return s + 1
  > }
  > print(wait(Light.red))
  > print(wait(Light.amber))
  > print(wait(Light.green))
  > EOF
  $ ./lab.exe build stmt.swift -o stmt && ./stmt
  31
  6
  1

An Int switch takes the first matching case and falls to `default` when none match — Swift does
NOT fall through from one case to the next:

  $ cat > ints.swift <<'EOF'
  > func name(_ n: Int) -> Int {
  >   switch n {
  >   case 1: return 10
  >   case 2: return 20
  >   case 3: return 30
  >   default: return 0
  >   }
  > }
  > print(name(1))
  > print(name(3))
  > print(name(9))
  > EOF
  $ ./lab.exe build ints.swift -o ints && ./ints
  10
  30
  0

A switch inside a loop runs the chain every iteration; `_` ignores a payload it does not need:

  $ cat > loop.swift <<'EOF'
  > enum Step {
  >   case up(Int)
  >   case down(Int)
  >   case stay
  > }
  > func apply(_ p: Int, _ s: Step) -> Int {
  >   switch s {
  >   case .up(let n): return p + n
  >   case .down(let n): return p - n
  >   case .stay: return p
  >   }
  > }
  > var pos = 0
  > var i = 0
  > while i < 6 {
  >   var s = Step.stay
  >   if i % 3 == 0 { s = Step.up(i) }
  >   if i % 3 == 1 { s = Step.down(1) }
  >   pos = apply(pos, s)
  >   i = i + 1
  > }
  > print(pos)
  > EOF
  $ ./lab.exe build loop.swift -o loop && ./loop
  1

A `default` arm catches every case not named, and the bound payload keeps its own value per arm:

  $ cat > deflt.swift <<'EOF'
  > enum Token {
  >   case num(Int)
  >   case plus
  >   case minus
  >   case eof
  > }
  > func weight(_ t: Token) -> Int {
  >   switch t {
  >   case .num(let n): return n * 100
  >   case .plus: return 1
  >   default: return -1
  >   }
  > }
  > print(weight(Token.num(7)))
  > print(weight(Token.plus))
  > print(weight(Token.minus))
  > print(weight(Token.eof))
  > EOF
  $ ./lab.exe build deflt.swift -o deflt && ./deflt
  700
  1
  -1
  -1
