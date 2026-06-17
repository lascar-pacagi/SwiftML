End-to-end: structs are value types — compile with ./lab.exe and RUN, matching swiftc.
RED until SILGen's + IRGen's TODO(10) holes are filled.

A struct lowers to an LLVM aggregate type; construction uses insertvalue, a read extractvalue:

  $ cat > p.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > let p = Point(x: 3, y: 4)
  > print(p.x)
  > print(p.y)
  > EOF
  $ ./lab.exe --emit-llvm p.swift | grep -c "%Point = type { i64, i64 }"
  1
  $ ./lab.exe build p.swift -o p && ./p
  3
  4

Value semantics: assigning a struct COPIES it, so mutating the copy leaves the original alone
(this is the whole point of a value type):

  $ cat > v.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 1, y: 2)
  > var q = p
  > q.x = 99
  > print(p.x)
  > print(q.x)
  > EOF
  $ ./lab.exe build v.swift -o v && ./v
  1
  99

A struct passed to a function is passed by value; nested structs work too:

  $ cat > f.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > struct Line {
  >   var a: Point
  >   var b: Point
  > }
  > func mx(_ l: Line) -> Int { return l.b.x }
  > print(mx(Line(a: Point(x: 0, y: 0), b: Point(x: 7, y: 9))))
  > EOF
  $ ./lab.exe build f.swift -o f && ./f
  7
