End-to-end: pattern matching makes enums usable — compile with ./lab.exe and RUN, matching swiftc.
RED until SILGen's + sema's TODO(12) holes are filled.

A `switch` reads the tag and binds associated values; here it destructures a `Shape`:

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

A tree of cases is just an ADT + a switch — a tiny interpreter (Milestone M3 in miniature):

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
  > print(eval(Op.add(3, 4)))
  > print(eval(Op.mul(6, 7)))
  > EOF
  $ ./lab.exe build eval.swift -o eval && ./eval
  7
  42

The lowering is a tag dispatch — `enum_tag`, then per-case `enum_payload` binding:

  $ ./lab.exe --emit-sil area.swift | grep -oE "enum_tag|enum_payload" | sort -u
  enum_payload
  enum_tag

An Int switch needs a `default`; a non-exhaustive enum switch is rejected, like swiftc:

  $ printf 'enum E { case a\n case b }\nlet e = E.a\nswitch e {\ncase .a: print(1)\n}\n' > ne.swift
  $ ./lab.exe --typecheck ne.swift 2>&1 | grep -o "switch must be exhaustive"
  switch must be exhaustive
