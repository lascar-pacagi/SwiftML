TODO(10c) struct-use syntax — call arguments retain optional labels, postfix member access
chains from left to right, and the one-level `p.x = value` form is a member-assignment statement.
`--emit-ast` keeps this independent of Sema and lowering.

Initializer labels are part of the AST; ordinary positional arguments still carry no label.

  $ printf 'let p = Point(x: 1, visible: true)\nadd(2, 3)\n' > init.swift
  $ ./lab.exe --emit-ast init.swift
  (let p (Point x:1 visible:true))
  (add 2 3)

Postfix parsing makes `line.b.x` a member of a member before the surrounding call is built.

  $ printf 'print(line.b.x)\n' > read.swift
  $ ./lab.exe --emit-ast read.swift
  (print (. (. line b) x))

The four-token lookahead recognizes a one-level member write, and its right side remains a
normal expression that may read a member.

  $ printf 'p.x = p.x + 1\n' > write.swift
  $ ./lab.exe --emit-ast write.swift
  (.= p x (+ (. p x) 1))
