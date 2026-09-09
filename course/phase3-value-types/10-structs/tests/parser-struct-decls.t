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
