`e as T`, through `--emit-ast`. Needs the `TODO(05f)` arm in the Pratt loop; the type name reader
and `cast_bp` are given. Nothing here touches sema.

`let x = 1 as Double` parses as an `Ascribe` node, not two statements.
`as` is not a binary operator — its right side is a type NAME, so it cannot go through
`binop_of_kind`; it gets its own arm, and the dump shows the type it carries:

  $ printf 'let x = 1 as Double\n' > r1.swift
  $ ./lab.exe --emit-ast r1.swift
  (let x (as Double 1))

`as` binds looser than `+` and tighter than `<` — Swift's CastingPrecedence.
So `1 + 2 as Double` coerces the SUM, and `1 < 2 as Int` coerces the right operand before the
comparison sees it. Both groupings match swiftc (`1 + 2 as Double` prints 3.0 there):

  $ printf 'let y = 1 + 2 as Double\nlet z = 1 < 2 as Int\n' > r2.swift
  $ ./lab.exe --emit-ast r2.swift
  (let y (as Double (+ 1 2)))
  (let z (< 1 (as Int 2)))
