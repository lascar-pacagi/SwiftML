TODO(10b) struct declarations — `parse_struct` records the name and each stored property in
source order, including whether it was introduced by `var` or `let`. `--emit-ast` stops before
Sema, so unresolved struct type names are fine here.

A one-line declaration uses semicolons as field separators and preserves `var` versus `let`.

  $ printf 'struct Point { var x: Int; let visible: Bool }\n' > point.swift
  $ ./lab.exe --emit-ast point.swift
  (struct Point (x:Int let visible:Bool))

A field type is a written name, so one struct may mention another before Sema resolves it.

  $ cat > box.swift <<'EOF'
  > struct Point {
  >   var x: Int
  > }
  > struct Box {
  >   var value: Point
  > }
  > EOF
  $ ./lab.exe --emit-ast box.swift
  (struct Point (x:Int))
  (struct Box (value:Point))

A declaration without a name reports at the `{`.

  $ printf 'struct { }\n' > bad-name.swift
  $ ./lab.exe --emit-ast bad-name.swift 2>&1 | head -1
  1:8: error: expected a struct name

A declaration without its opening brace reports at the first field keyword.

  $ printf 'struct P var x: Int }\n' > bad-open.swift
  $ ./lab.exe --emit-ast bad-open.swift 2>&1 | head -1
  1:10: error: expected '{'

Only `var` and `let` introduce stored properties in this subset.

  $ printf 'struct P { x: Int }\n' > bad-field.swift
  $ ./lab.exe --emit-ast bad-field.swift 2>&1 | head -1
  1:12: error: expected a stored property: 'var name: Type'

A stored property needs a name and a written type.

  $ printf 'struct P { var : Int }\n' > bad-property-name.swift
  $ ./lab.exe --emit-ast bad-property-name.swift 2>&1 | head -1
  1:16: error: expected a property name
  $ printf 'struct P { var x: }\n' > bad-property-type.swift
  $ ./lab.exe --emit-ast bad-property-type.swift 2>&1 | head -1
  1:19: error: expected a property type

Two fields need a newline or semicolon between them.

  $ printf 'struct P { var x: Int var y: Int }\n' > bad-separator.swift
  $ ./lab.exe --emit-ast bad-separator.swift 2>&1 | head -1
  1:23: error: expected newline or end of declaration

A declaration that reaches end of input without `}` reports the missing delimiter there.

  $ printf 'struct P { var x: Int' > bad-close.swift
  $ ./lab.exe --emit-ast bad-close.swift 2>&1 | head -1
  1:22: error: expected '}'
