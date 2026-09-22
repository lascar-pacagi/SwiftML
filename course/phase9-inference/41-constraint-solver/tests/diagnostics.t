What the solver says when there is no solution — the hardest part of the design, and the one
place a constraint-based checker starts at a disadvantage. `Sema` in concept 05 knew which
rule failed, because a rule had to fail for it to stop. A search that comes back empty knows
only that the system is unsatisfiable. `Cssolver.diagnose` (given) recovers a blame in two
stages; §6 exercise 3 is how swiftc does it properly.

Stage one: an overload set where nothing on offer fits its own operands. Concept 05's two
wordings, chosen the same way.

  $ printf 'let b = 1 + true\n' > d1.swift
  $ ./lab.exe --typecheck d1.swift; echo "exit=$?"
  1:9: error: binary operator '+' cannot be applied to operands of type 'Int' and 'Bool'
  let b = 1 + true
          ^
  exit=1

Operands that agree with each other and still have no overload get the `two` wording, and
this one is swiftc's verbatim.

  $ printf 'let c = true < false\n' > d2.swift
  $ ./lab.exe --typecheck d2.swift; echo "exit=$?"
  1:9: error: binary operator '<' cannot be applied to two 'Bool' operands
  let c = true < false
          ^
  exit=1

A literal is shown at its DEFAULT type. The solver never bound it — nothing succeeded —
but telling the reader the operand is `_` helps nobody.

  $ printf 'let s = "a" + 1\n' > d3.swift
  $ ./lab.exe --typecheck d3.swift; echo "exit=$?"
  1:9: error: binary operator '+' cannot be applied to operands of type 'String' and 'Int'
  let s = "a" + 1
          ^
  exit=1

Stage two: every overload set is fine on its own, so the conflict comes from a type someone
WROTE. Drop each written type in turn and solve the rest; what the rest says is what the
annotation disagrees with.

  $ printf 'let x: Bool = 1 + 2\n' > d4.swift
  $ ./lab.exe --typecheck d4.swift; echo "exit=$?"
  1:15: error: cannot convert value of type 'Int' to specified type 'Bool'
  let x: Bool = 1 + 2
                ^
  exit=1

The same stage catches a literal that cannot take the type it was given.

  $ printf 'let y: String = 1\n' > d5.swift
  $ ./lab.exe --typecheck d5.swift; echo "exit=$?"
  1:1: error: type of expression is ambiguous without a type annotation
  let y: String = 1
  ^
  exit=1

No declaration of the right arity is a resolution failure, not a type error.

  $ cat > d6.swift <<'EOF'
  > func f(_ x: Int) -> Int { return x }
  > let a = f(1, 2)
  > EOF
  $ ./lab.exe --typecheck d6.swift; echo "exit=$?"
  2:9: error: no exact matches in call to global function 'f'
  let a = f(1, 2)
          ^
  exit=1

Two declarations with the SAME signature are still a redeclaration: overloading needs the
signatures to differ, and the return type counts.

  $ cat > d7.swift <<'EOF'
  > func f(_ x: Int) -> Int { return x }
  > func f(_ x: Int) -> Int { return x }
  > EOF
  $ ./lab.exe --typecheck d7.swift; echo "exit=$?"
  2:1: error: invalid redeclaration of 'f'
  func f(_ x: Int) -> Int { return x }
  ^
  exit=1

Names are resolved before any solving, so an unknown one is reported by generation and the
solver never sees it.

  $ printf 'let a = nope + 1\n' > d8.swift
  $ ./lab.exe --typecheck d8.swift; echo "exit=$?"
  1:9: error: cannot find 'nope' in scope
  let a = nope + 1
          ^
  exit=1
