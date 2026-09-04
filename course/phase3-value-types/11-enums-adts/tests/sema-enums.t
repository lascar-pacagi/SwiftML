The enum rules of sema — GIVEN code, so this file is green from the start; it is here so the
diagnostics the front end owes you are on record before you lower anything. `--typecheck` stops
after sema: exit 0 and silence is "accepted", exit 1 with `line:col: error: …` is not.

A well-formed enum program — declaration, a case, `==`, `.rawValue`, an enum in a `var` — is
accepted:

  $ cat > ok.swift <<'EOF'
  > enum Color { case red, green, blue }
  > enum Dir: Int { case north, south }
  > var c = Color.red
  > c = Color.blue
  > let same = c == Color.blue
  > print(same)
  > print(Dir.south.rawValue)
  > EOF
  $ ./lab.exe --typecheck ok.swift

`Color.blue` on a two-case enum is `type 'Color' has no member 'blue'` — swiftc's own wording:

  $ cat > nocase.swift <<'EOF'
  > enum Color { case red, green }
  > let c = Color.blue
  > EOF
  $ ./lab.exe --typecheck nocase.swift
  2:9: error: type 'Color' has no member 'blue'
  [1]

`S.pair(1)` gives one associated value where the case declares two:

  $ cat > arity.swift <<'EOF'
  > enum S { case pair(Int, Int) }
  > let s = S.pair(1)
  > EOF
  $ ./lab.exe --typecheck arity.swift
  2:9: error: enum case 'S.pair' expects 2 associated value(s) but 1 given
  [1]

`S.pair(1, true)` checks each associated value against its declared type:

  $ cat > payloadty.swift <<'EOF'
  > enum S { case pair(Int, Int) }
  > let s = S.pair(1, true)
  > EOF
  $ ./lab.exe --typecheck payloadty.swift
  2:19: error: cannot convert value of type 'Bool' to specified type 'Int'
  [1]

`E.a` names a case that carries a value, with no arguments — a case is not a value here:

  $ cat > bare.swift <<'EOF'
  > enum E { case a(Int) }
  > let e = E.a
  > EOF
  $ ./lab.exe --typecheck bare.swift
  2:9: error: enum case 'E.a' requires arguments
  [1]

`==` on an associated-value enum is refused: comparing tags would call `a(1)` equal to `a(2)`,
and the `Equatable` conformance that compares payloads is not synthesized (Exercise 2):

  $ cat > eq.swift <<'EOF'
  > enum S {
  >   case a(Int)
  >   case b
  > }
  > print(S.a(1) == S.a(1))
  > EOF
  $ ./lab.exe --typecheck eq.swift
  5:7: error: type 'S' does not conform to protocol 'Equatable'
  [1]

`==` on a payload-free enum is accepted — that one IS implicitly Equatable:

  $ cat > eqok.swift <<'EOF'
  > enum Color { case red, green }
  > print(Color.red == Color.green)
  > EOF
  $ ./lab.exe --typecheck eqok.swift

`.rawValue` exists only on an enum declared `: Int`; on a plain one it is not a member:

  $ cat > raw.swift <<'EOF'
  > enum Color { case red }
  > print(Color.red.rawValue)
  > EOF
  $ ./lab.exe --typecheck raw.swift
  2:7: error: value of type 'Color' has no member 'rawValue'
  [1]

An enum and a struct share one namespace, so the second declaration of the name is invalid:

  $ cat > redecl.swift <<'EOF'
  > enum A { case one }
  > struct A {
  >   var x: Int
  > }
  > EOF
  $ ./lab.exe --typecheck redecl.swift
  2:1: error: invalid redeclaration of 'A'
  [1]

An enum names a type: it annotates a `let`, and it is a parameter and a return type:

  $ cat > types.swift <<'EOF'
  > enum Color { case red, green }
  > func flip(_ c: Color) -> Color {
  >   if c == Color.red { return Color.green }
  >   return Color.red
  > }
  > let c: Color = flip(Color.red)
  > print(c == Color.green)
  > EOF
  $ ./lab.exe --typecheck types.swift

`print(c)` of a whole enum is refused up front (swiftc prints the case name `red` through
reflection — a documented divergence, §2) instead of crashing IRGen:

  $ cat > printenum.swift <<'EOF'
  > enum Color { case red, green }
  > let c = Color.red
  > print(c)
  > EOF
  $ ./lab.exe --typecheck printenum.swift
  3:7: error: cannot print a value of type 'Color' (only Int, Double, Bool and String)
  [1]
