TODO(10b) struct declarations — `parse_struct` records the name and each stored property in
source order, including whether it was introduced by `var` or `let`. `--emit-ast` stops before
Sema, so unresolved struct type names are fine here.

A one-line declaration uses semicolons as field separators and preserves `var` versus `let`.

  $ printf 'struct Point { var x: Int; let visible: Bool }\n' > point.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast point.swift
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
  $ python3 timeout.py 2 ./lab.exe --emit-ast box.swift
  (struct Point (x:Int))
  (struct Box (value:Point))

A declaration without a name reports at the `{`.

  $ printf 'struct { }\n' > bad-name.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-name.swift 2>&1 | head -3
  1:8: error: expected a struct name
  struct { }
         ^

A declaration without its opening brace reports at the first field keyword.

  $ printf 'struct P var x: Int }\n' > bad-open.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-open.swift 2>&1 | head -3
  1:10: error: expected '{'
  struct P var x: Int }
           ^

Only `var` and `let` introduce stored properties in this subset.

  $ printf 'struct P { x: Int }\n' > bad-field.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-field.swift 2>&1 | head -3
  1:12: error: expected a stored property: 'var name: Type'
  struct P { x: Int }
             ^

A member that is not a stored property, here an `init` (not in this subset), is reported once;
the parser skips it, body included, and the rest of the program still parses.

  $ cat > bad-member.swift <<'EOF'
  > struct P {
  >   var x: Int
  >   init(x: Int) { self.x = x }
  >   var y: Int
  > }
  > let p = P(x: 1, y: 2)
  > EOF
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-member.swift 2>&1
  3:3: error: expected a stored property: 'var name: Type'
    init(x: Int) { self.x = x }
    ^
  [1]

Blank lines and comment lines inside a struct body are allowed, between fields and before
the `}`: after lexing, a comment line is just another newline.

  $ cat > blank-lines.swift <<'EOF'
  > struct P {
  >   var x: Int // the first field
  > 
  >   // the second field
  >   var y: Int
  > 
  > }
  > EOF
  $ python3 timeout.py 2 ./lab.exe --emit-ast blank-lines.swift
  (struct P (x:Int y:Int))

A bad member as the LAST one is reported once too, and the `}` after it still closes the
struct.

  $ cat > bad-last.swift <<'EOF'
  > struct P {
  >   var x: Int
  >   init(x: Int) { self.x = x }
  > }
  > let p = P(x: 1)
  > EOF
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-last.swift 2>&1
  3:3: error: expected a stored property: 'var name: Type'
    init(x: Int) { self.x = x }
    ^
  [1]

A bad member over several lines is skipped whole, braces included, and reported once.

  $ cat > bad-multiline.swift <<'EOF'
  > struct P {
  >   var x: Int
  >   init(x: Int) {
  >     self.x = x
  >   }
  >   var y: Int
  > }
  > let p = P(x: 1, y: 2)
  > EOF
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-multiline.swift 2>&1
  3:3: error: expected a stored property: 'var name: Type'
    init(x: Int) {
    ^
  [1]

A stored property needs a name and a written type.

  $ printf 'struct P { var : Int }\n' > bad-property-name.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-property-name.swift 2>&1 | head -3
  1:16: error: expected a property name
  struct P { var : Int }
                 ^

A stored property needs a colon between its name and type.

  $ printf 'struct P { var x Int }\n' > bad-property-colon.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-property-colon.swift 2>&1 | head -3
  1:18: error: expected ':'
  struct P { var x Int }
                   ^

A stored property needs a written type after its colon.

  $ printf 'struct P { var x: }\n' > bad-property-type.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-property-type.swift 2>&1 | head -3
  1:19: error: expected a property type
  struct P { var x: }
                    ^

Two fields need a newline or semicolon between them.

  $ printf 'struct P { var x: Int var y: Int }\n' > bad-separator.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-separator.swift 2>&1 | head -3
  1:23: error: expected newline or end of declaration
  struct P { var x: Int var y: Int }
                        ^

A declaration that reaches end of input without `}` reports the missing delimiter there.

  $ printf 'struct P { var x: Int' > bad-close.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-close.swift 2>&1 | head -3
  1:22: error: expected '}'
  struct P { var x: Int
                       ^
