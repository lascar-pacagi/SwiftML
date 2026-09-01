The type annotation, through `--emit-ast`. Needs the `TODO(05)` hole in `parse_annot`; it does
not touch sema (an unknown type name is Sema's job, not the parser's).

`let d: Double = 3.14` keeps the annotation; `let x = 1` has none.
`parse_annot` returns `Some name` when the next token is a `:` and `None` otherwise — the dump
prints the annotated form as `(let d : Double …)`:

  $ printf 'let d: Double = 3.14\nlet x = 1\n' > p2.swift
  $ ./lab.exe --emit-ast p2.swift
  (let d : Double 3.14)
  (let x 1)

The annotation is just an identifier to the parser — `String` and `Bool` too.
Nothing here checks that the name exists or that the value matches it; that is `Types.of_name`
and `check_expr` in sema:

  $ printf 'let s: String = "hi"\nlet b: Bool = true\n' > p3.swift
  $ ./lab.exe --emit-ast p3.swift
  (let s : String "hi")
  (let b : Bool true)
