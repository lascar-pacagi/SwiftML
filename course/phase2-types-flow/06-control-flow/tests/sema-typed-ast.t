What the checker PRODUCES for control flow, through `--emit-tast`. Concept 05 introduced the idea
— sema returns a typed tree rather than a verdict — and this concept's statements join it. The
back end (concept 08) consumes this and re-derives nothing; PLAN.md §0.1 says why.

Blocks, the loop variable and the two branches all come back as typed nodes, and every name that
resolved is a `local`. Note `i` is a `local` inside the body and nowhere else — the scope rule is
recorded in the tree, not re-discovered later:

  $ printf 'var t = 0\nfor i in 0 ..< 3 {\n  if i > 1 { t = t + i } else { t = t - 1 }\n}\nprint(t)\n' > c1.swift
  $ ./lab.exe --emit-tast c1.swift
  (var t (int_lit 0 : Int))
  (for i (int_lit 0 : Int) (int_lit 3 : Int) {(if (> (local i : Int) (int_lit 1 : Int) : Bool) {(= t (+ (local t : Int) (local i : Int) : Int))} {(= t (- (local t : Int) (int_lit 1 : Int) : Int))})})
  (print (local t : Int) : Int)

The literal coercion is recorded through a comparison inside a condition too — `2` carries Double
because the other operand is one, and a back end never has to notice that for itself:

  $ printf 'let d = 1.5\nwhile d * 2 > 1.0 { break }\n' > c2.swift
  $ ./lab.exe --emit-tast c2.swift
  (let d (double_lit 1.5 : Double))
  (while (> (* (local d : Double) (int_lit 2 : Double) : Double) (double_lit 1 : Double) : Bool) {(break)})

A condition that is not Bool produces no tree at all — the checker returns nothing when it found
errors, so no later stage can be handed a program that failed to check:

  $ printf 'let i = 1\nif i { print(1) }\n' > c3.swift
  $ ./lab.exe --emit-tast c3.swift 2>&1; echo "exit=$?"
  2:4: error: cannot convert value of type 'Int' to specified type 'Bool'
  if i { print(1) }
     ^
  exit=1
