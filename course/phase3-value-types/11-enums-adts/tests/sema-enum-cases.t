TODO(11e) enum construction — Sema checks case lookup, whether arguments are required,
payload arity, and every associated value against its declared type.

Payload-free and payload-carrying cases produce values of the declared enum type.

  $ cat > accepted.swift <<'EOF'
  > enum Command { case stop; case move(Int, Int) }
  > let stopped: Command = Command.stop
  > let moving: Command = Command.move(3, 4)
  > EOF
  $ ./lab.exe --typecheck accepted.swift

An unknown case is reported on the enum type.

  $ printf 'enum Color { case red }\nlet c = Color.blue\n' > unknown.swift
  $ ./lab.exe --typecheck unknown.swift
  2:9: error: type 'Color' has no member 'blue'
  [1]

A payload case requires its arguments.

  $ printf 'enum E { case value(Int) }\nlet e = E.value\n' > missing.swift
  $ ./lab.exe --typecheck missing.swift
  2:9: error: enum case 'E.value' requires arguments
  [1]

The number of supplied associated values must match the case declaration.

  $ printf 'enum E { case pair(Int, Int) }\nlet e = E.pair(1)\n' > arity.swift
  $ ./lab.exe --typecheck arity.swift
  2:9: error: enum case 'E.pair' expects 2 associated value(s) but 1 given
  [1]

Each associated value is checked against its corresponding declared type.

  $ printf 'enum E { case pair(Int, Int) }\nlet e = E.pair(1, true)\n' > types.swift
  $ ./lab.exe --typecheck types.swift
  2:19: error: cannot convert value of type 'Bool' to specified type 'Int'
  [1]
