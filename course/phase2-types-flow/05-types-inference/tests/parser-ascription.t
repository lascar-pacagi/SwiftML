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

`1 as 5` reports swiftc's own wording, at swiftc's own column.
The type name is read by the given `parse_ident_ty`, which builds `"expected " ^ what` — so the
`what` phrase *is* the message. Passing `"type after 'as'"` reproduces
`diag::expected_type_after_as` exactly (swiftc: `1:14: error: expected type after 'as'`). The
second line is the parser recovering: it did not consume a type, so the statement ends here.

  $ printf 'let y = 1 as 5\n' > r3.swift
  $ ./lab.exe --emit-ast r3.swift 2>&1; echo "exit=$?"
  1:14: error: expected type after 'as'
  1:14: error: expected newline or end of statement
  exit=1
