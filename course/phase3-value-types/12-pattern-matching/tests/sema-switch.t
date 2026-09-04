The pattern-typing rules of sema — GIVEN code, so this file is green from the start (the one
rule you write, exhaustiveness, has its own file). `--typecheck` stops after sema: exit 0 and
silence is "accepted", exit 1 with `line:col: error: …` is not.

A complete switch over an enum, with bindings and an `_`, is accepted, and so is an Int switch
with a `default`:

  $ cat > ok.swift <<'EOF'
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
  > print(area(Shape.dot))
  > let n = 1
  > switch n {
  > case 1: print(10)
  > default: print(0)
  > }
  > EOF
  $ ./lab.exe --typecheck ok.swift

A pattern binding one value where the case declares two is refused, and the binding it promised
never happens, so `w` is not in scope in that arm. (swiftc ACCEPTS this one — it reads `.rect(let
w)` as binding the whole `(Int, Int)` tuple to `w`, a type our subset has no room for; §2.)

  $ cat > arity.swift <<'EOF'
  > enum Shape {
  >   case rect(Int, Int)
  >   case dot
  > }
  > let s = Shape.dot
  > switch s {
  > case .rect(let w): print(w)
  > case .dot: print(0)
  > }
  > EOF
  $ ./lab.exe --typecheck arity.swift
  6:1: error: pattern '.rect' binds 1 value(s) but case 'rect' has 2 associated value(s)
  7:26: error: cannot find 'w' in scope
  [1]

A pattern naming a case the enum does not have is `type 'E' has no member 'nope'`:

  $ cat > nocase.swift <<'EOF'
  > enum E { case a, b }
  > let e = E.a
  > switch e {
  > case .a: print(1)
  > case .nope: print(2)
  > default: print(3)
  > }
  > EOF
  $ ./lab.exe --typecheck nocase.swift
  3:1: error: type 'E' has no member 'nope'
  [1]

An Int pattern cannot match an enum, and an enum-case pattern cannot match an Int:

  $ cat > mixed.swift <<'EOF'
  > enum E { case a, b }
  > let e = E.a
  > switch e {
  > case 1: print(1)
  > default: print(0)
  > }
  > let n = 3
  > switch n {
  > case .a: print(1)
  > default: print(0)
  > }
  > EOF
  $ ./lab.exe --typecheck mixed.swift
  3:1: error: expression pattern of type 'Int' cannot match values of type 'E'
  8:1: error: enum case '.a' cannot match values of type 'Int'
  [1]

`switch` needs something with a discriminant: a Bool subject has no tag to read:

  $ cat > bool.swift <<'EOF'
  > let b = true
  > switch b {
  > case 1: print(1)
  > default: print(0)
  > }
  > EOF
  $ ./lab.exe --typecheck bool.swift
  2:1: error: cannot 'switch' over a value of type 'Bool'
  [1]

A binding belongs to ITS arm only — `r` is out of scope after the switch, and in the other arm:

  $ cat > scope.swift <<'EOF'
  > enum Shape {
  >   case circle(Int)
  >   case dot
  > }
  > let s = Shape.dot
  > switch s {
  > case .circle(let r): print(r)
  > case .dot: print(r)
  > }
  > print(r)
  > EOF
  $ ./lab.exe --typecheck scope.swift
  8:18: error: cannot find 'r' in scope
  10:7: error: cannot find 'r' in scope
  [1]

A bound value carries its declared type: binding an `Int` payload and using it as a `Bool` fails:

  $ cat > bindty.swift <<'EOF'
  > enum Shape {
  >   case circle(Int)
  >   case dot
  > }
  > let s = Shape.dot
  > switch s {
  > case .circle(let r): let b: Bool = r
  > case .dot: print(0)
  > }
  > EOF
  $ ./lab.exe --typecheck bindty.swift
  7:36: error: cannot convert value of type 'Int' to specified type 'Bool'
  [1]
